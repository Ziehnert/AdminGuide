#!/bin/bash

## CONFIGURATION ###
ADM_NAME='admin'
ADM_GID=997
ADM_HOME='/home/admin'
ADM_USERS=('user')

declare -A HELPER=(
  ["proxy"]="172.30.0.0/24"
)
### END of CONFIGURATION ###

function create_compose() {
  echo -e "version: '3.9'\n\n\n" >>${compose}
  echo -e "networks:" >>${compose}
  echo -e "  default:" >>${compose}

  # define helper networks
  for helper_name in ${!HELPER[@]}; do
    echo -e "  ${helper_name}:" >>${compose}
    echo -e "    external:" >>${compose}
    echo -e "      name: ${helper_name}" >>${compose}
  done
}

# require root privileges
if [[ $(/usr/bin/id -u) != "0" ]]; then
  echo "Please run the script as root!"
  exit 1
fi

if [[ ${RERUN} == 1 ]]; then
  echo "You already ran the script, if you really want to run the script again set 'RERUN=0'. (This might break your system!)"
  exit 1
fi

# add rerun=1 variable to prevent postinstall to be executed multiple times
sed -i '2 i\RERUN=1' ${0}

echo ">>> Installing Software"
apt-get update
apt-get install sudo curl wget borgbackup bc

# install docker if not already installed
if [[ -z $(which docker) ]]; then
  curl https://get.docker.com | bash
fi

# install docker-compose if not already installed
if [[ -z $(which docker-compose) ]]; then
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# remove trailing slash from ADM_HOME
[[ "${ADM_HOME}" == */ ]] && ADM_HOME="${ADM_HOME::-1}"

# create admin group, add members to group and set permissions
echo ">>> Creating Admin Setup"
/usr/sbin/groupadd -g ${ADM_GID} ${ADM_NAME}
mkdir ${ADM_HOME}
chown -R root:${ADM_NAME} ${ADM_HOME}
chmod -R 775 ${ADM_HOME}
for user in ${ADM_USERS[@]}; do
  # check if user exists
  if [ ! $(sed -n "/^${user}/p" /etc/passwd) ]; then
    /usr/sbin/useradd --create-home --shell=/bin/bash ${user}
  fi
  /usr/sbin/usermod --append --groups=sudo,${ADM_NAME} ${user}

  # add aliases
  echo -e '\nalias dc="sudo docker-compose "' | tee -a /home/${user}/.bashrc > /dev/null

  # check if exist
  [ ! -h "/home/{user}/admin" ] && ln -s ${ADM_HOME} /home/${user}/admin
done

# create helper networks
for name in ${!HELPER[@]}; do
  docker network inspect ${name} >/dev/null 2>&1 || docker network create --subnet ${HELPER[${name}]} ${name}
done

# adjust permissions
chown -R root:admin ${ADM_HOME}
find ${ADM_HOME} -type d -exec chmod 0775 {} \;
find ${ADM_HOME} -type f -exec chmod 0664 {} \;
find ${ADM_HOME}/tools/ -type f -exec chmod 0775 {} \;

wget -q https://raw.githubusercontent.com/felbinger/scripts/master/genpw.sh -O /usr/local/bin/genpw
chmod +x /usr/local/bin/genpw
