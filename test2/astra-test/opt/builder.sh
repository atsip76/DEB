#!/bin/bash - 
#===============================================================================
#
#          FILE: postinst
# 
#         USAGE: ./postinst 
# 
#   DESCRIPTION: test
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Anatoly Afanasiev 
#  ORGANIZATION: 
#       CREATED: 11.07.2022 11:57:14
#      REVISION: 0.1
#===============================================================================
set -o nounset                              # Treat unset variables as an error
sudo apt update && sudo apt upgrade -y
cd ~
mkdir deb #создаем директорию для собранных пакетов, логов, метафайлов
#назначаем приложения для сборки помещая их в массив pkg
pkg=("bash" "gawk" "sed")
#устанавливаем aptly "швейцарский нож" для создания локальных репозиториев, зеркал и снимков
#устанавливаем инструмент для проверки пакетов на предмет ошибок и прочие необходимые инструменты
apt install -y aptly lintian gnupg wget git mc debootstrap
#импортируем связку ключей Debian по умолчанию
gpg --no-default-keyring --keyring /usr/share/keyrings/debian-archive-keyring.gpg --export | gpg --no-default-keyring --keyring trustedkeys.gpg --import
#создаем cache нужных приложений для сборки (bash gawk aptly) из массива pkg
aptly mirror create -architectures=amd64 -with-sources -filter="Priority (required) | Priority (important) | Priority (standard) | ${pkg[0]} | ${pkg[1]} | ${pkg[2]}" -filter-with-deps byllseye-main http://ftp.ru.debian.org/debian/ bullseye main
#Обновляем кеш
aptly mirror update byllseye-main
#Узнаем все зависимости пакетов, удаляем пробелы, все номера версий в скобках
rm ~/DEPENDS
for i in ${pkg[*]};
do aptly package show $i |grep Depends |awk  '{$1=""; print $0}' |sed s/' '//g | sed 's/([^)]*)//g' | sed 's/<[^>]*>//g' | sed 's/\[[^)]*\]//g' | sed 's/libselinux-dev/libselinux1-dev/' >> ~/DEPENDS;
done
#формируем упорядоченный файл зависимостей DEPEND для сбoрки окружения в debootstrap bullseye
array=($(cat ~/DEPENDS | tr "," "\n"))
for i in "${array[@]}"; do echo $i; done | sort |uniq > DEPENDS
#присвоение переменной DEP строки из файла зависимостей dep с удалением перводов строк, замена на ,(формируем непрерывную строку)
DEP=$(cat DEPENDS | tr '\n ' ',')
#Готoвим debootstrap bullseye для сборки в дире ~/test со всеми необходимыми зависимостями и утилитами построения пакетов из исходников (devscripts)
debootstrap --variant=buildd --components=main,contrib,non-free --include=build-essential,adduser,fakeroot,devscripts,$DEP --arch=amd64 bullseye ~/test http://mirror.yandex.ru/debian/
#добавляем список адресаов источников репозиториев пакетов и сырцов в apt
echo "deb http://deb.debian.org/debian/ bullseye main
deb-src http://deb.debian.org/debian/ bullseye main
deb http://security.debian.org/debian-security bullseye-security main
deb-src http://security.debian.org/debian-security bullseye-security main
deb http://deb.debian.org/debian/ bullseye main
deb-src http://deb.debian.org/debian/ bullseye main
deb http://security.debian.org/debian-security bullseye-security main
deb-src http://security.debian.org/debian-security bullseye-security main" > test/etc/apt/sources.list
#монтируем виртуальные фс хост системы в debootstrap
export MY_CHROOT=~/test
mount -t proc proc $MY_CHROOT/proc 
mount --rbind /sys $MY_CHROOT/sys
mount --make-rslave $MY_CHROOT/sys  
mount --rbind /dev $MY_CHROOT/dev
mount --make-rslave $MY_CHROOT/dev
#создаем непривелигированного пользователя системы с bash оболочкой для корректной сборки sed (panic-tests.sh 
#при сборке приложения sed должен запускаться от непривелигированного пользователя)
#создаем каталог для выполнения сборки и переходим в него
#Производим подготовку сборочного окружения в среде debootstrap:
#обновляем древо портов
chroot ~/test /bin/bash -c "useradd -m -s /bin/bash builder && mkdir /opt/deb && apt update && apt list --upgradable"
#даем разрешения на диру пользователю для выполнения компиляции
#утилита построения пакета из исходников (devscripts)
#выкачиваем исходники заданных приложений
for i in ${pkg[*]};
 do chroot ~/test /bin/bash -c "cd /opt/deb && apt source $i && chown -R builder /opt/deb";
done
#выполняем компиляцию и сборку пакета без криптоподписи и используя утилиту fakeroot для обхода привелегий рута, послесборки возврат на уровень выше и интерация повторяется для след. приложения
for i in ${pkg[*]};
 do chroot ~/test /bin/bash -c "cd /opt/deb && cd $i-* && su builder -c 'dpkg-buildpackage -rfakeroot -b -uc -us'";
done

#перемещаем собранные пакеты, логи, метафайлы в директорию deb домашнего каталога хост системы
mv ~/test/opt/deb/*.deb ~/deb/
mv ~/test/opt/deb/*.changes ~/deb/
mv ~/test/opt/deb/*.buildinfo ~/deb/
#проверяем пакеты на типичные ошибки в структуре
#cd ~/DEB/
#lintian *.deb
