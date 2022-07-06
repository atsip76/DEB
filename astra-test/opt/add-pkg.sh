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
#создаем пользователя системы с bash оболочкой для корректной сборки sed (panic-tests.sh 
#при сборке приложения sed должен запускаться от непривелигированного пользователя)
/sbin/useradd  -m -s /bin/bash work-test
#создаем каталог для выполнения сборки и переходим в него
mkdir /opt/deb
cd /opt/deb
#добавляем список адресаов источников репозиториев пакетов и сырцов в apt
echo "deb http://deb.debian.org/debian/ bullseye main
deb-src http://deb.debian.org/debian/ bullseye main
deb http://security.debian.org/debian-security bullseye-security main
deb-src http://security.debian.org/debian-security bullseye-security main
deb http://deb.debian.org/debian/ bullseye main
deb-src http://deb.debian.org/debian/ bullseye main
deb http://security.debian.org/debian-security bullseye-security main
deb-src http://security.debian.org/debian-security bullseye-security main" > /etc/apt/sources.list
#Производим подготовку сборочного окружения в среде debootstrap:
#обновляем древо портов
/bin/apt update
/bin/apt list --upgradable
#выкачиваем исходники заданных приложений
for i in ${pkg[*]}; do /bin/apt source $i; done
#даем разрешения на диру временному пользователю для выполнения компиляции
chown -R work-test /opt/deb
#устанавливаем все зависимости и необходимые утилиты для последующей компиляции и сборки пакетов
/bin/apt install -y fakeroot
for i in ${pkg[*]}; do /bin/apt build-dep -y $i; done
#начинаем основной цикл установки
for i in ${pkg[*]};
do
cd $i-* && #переходим в директорию исходников компилируемого приложения
#выполняем компиляцию и сборку пакета без криптоподписи и используя утилиту fakeroot для обхода привелегий рута, послесборки возврат на уровень выше и интерация повторяется для след. приложения
su work-test -c 'dpkg-buildpackage -rfakeroot -b -uc -us' && cd ..;
done
#зачищаем диру от архивов исходников и папок сборки, оставляем собранные пакеты, логи
for i in ${pkg[*]};
do
find . -type d -name "$i-*" -exec rm -r {} +;
done
rm *.tar.xz
#удаляем временного пользователя
/sbin/deluser --remove-home work-test
#удаляем скрипт сборки
rm /opt/add-pkg.sh
