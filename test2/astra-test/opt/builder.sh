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
#       CREATED: 01.07.2022 11:57:14
#      REVISION: 0.1
#===============================================================================
set -o nounset                              # Treat unset variables as an error
#назначаем приложения для сборки помещая их в массив pkg
pkg=("bash" "gawk" "sed")
#устанавливаем aptly "швейцарский нож" для создания локальных репозиториев, зеркал и снимков
#устанавливаем инструмент для проверки пакетов на предмет ошибок и соответствия стандартам (lintian)
api install aptly lintian
#создаем диру для собранных пакетов, логов, метафайлов в домашней дирректории
mkdir ~/DEB
#импортируем связку ключей Debian по умолчанию
gpg --no-default-keyring --keyring /usr/share/keyrings/debian-archive-keyring.gpg --export | gpg --no-default-keyring --keyring trustedkeys.gpg --import
#создаем кеш нужных приложений для сборки (bash gawk aptly) из массива pkg
aptly mirror create -architectures=amd64 -with-sources -filter='Priority (required) | Priority (important) | Priority (standard) | ${pkg[0]} | ${pkg[1]} |${pkg[2]} ' -filter-with-deps byllseye-main http://ftp.ru.debian.org/debian/ bullseye main
#Обновляем кеш
aptly mirror update byllseye-main
#Узнаем все зависимости пакетаов, удаляем пробелы, все номера версий в скобках, формируем единый список зависимостей пакетов для сборки
#сформированный и упорядоченный список зависимостей сохраняем в файле dep для сб орки окружения в debootstrap bullseye
rm dep 
for i in ${pkg[*]};
do aptly package show $i |grep Depends: |awk  '{$1=""; print $0}' |sed s/' '//g | sed 's/([^)]*)//g' | sed 's/<[^>]*>//g' | sed 's/\[[^)]*\]//g' >> dep;
done
#присвоение переменной DEP строки из файла зависимостей dep с удалением перводов строк (формируем непрерывную строку)
DEP=$(cat dep | tr '\n ' ',')
#Готвим debootstrap bullseye для сборки в дире ./test со всеми необходимыми зависимостями и утилитами построения пакетов из исходников (devscripts)
debootstrap --variant=buildd --components=main,contrib,non-free --include=build-essential,adduser,fakeroot,devscripts,$DEP --arch=amd64 bullseye ./test http://mirror.yandex.ru/debian/
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
export MY_CHROOT=/root/test
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
#выкачиваем исходники заданных приложений
#даем разрешения на диру пользователю для выполнения компиляции
#устанавливаем инструмент для проверки пакетов на предмет ошибок и соответствия стандартам (install) и  утилита построения пакета из исходников (devscripts)
#выполняем компиляцию и сборку пакета без криптоподписи и используя утилиту fakeroot для обхода привелегий рута, послесборки возврат на уровень выше и интерация повторяется для след. приложения
chroot /root/test /bin/bash -c "useradd  -m -s /bin/bash builder && mkdir /opt/deb && cd /opt/deb && apt update && apt list --upgradable &&\
for i in ${pkg[*]}; do apt source $i; done && chown -R builder /opt/deb && for i in ${pkg[*]}; do cd $i-* && su builder -c 'dpkg-buildpackage -rfakeroot -b -uc -us' && cd ..; done"
#перемещаем собранные пакеты, логи, метафайлы в директорию DEB домашнего каталога хост системы
mv ~/test/opt/deb/ *.deb *.changes *.buildinfo *.dsc ~/DEB/
#проверяем пакеты на типичные ошибки в структуре
cd ~/DEB/
lintian *.deb
