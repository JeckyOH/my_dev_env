#!/usr/bin/env bash

set -ex
# Staging for packages built from source.
PACKAGE_ROOT=${PACKAGE_ROOT:-$HOME/packages}
mkdir -p $PACKAGE_ROOT

LATEST_PROTO=3.6.1
LATEST_PYTHON37=3.7.6

VIRTUALENV_ROOT=${VIRTUALENV_ROOT:-$HOME/virtualenv}

# Virtualenv environment to activate (passed in from jenkins build_common.sh)
VE_ENV=${VENV:-v1}

# By defualt just install python packages.
DO_MACHINE_INSTALL=${DO_MACHINE_INSTALL:-false}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [ `uname` = "Darwin" ]; then
  MACOS=true
  UPDATE="brew_update"
  INSTALL="brew_install_or_update_packages"
  CASK_INSTALL="brew_cask_install_or_update_packages"
  XCODE_SELECT=/usr/bin/xcode-select
  which brew || {
    echo ERROR: Missing homebrew.  Install from http://brew.sh/ and try again.
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  }
  brew tap homebrew/core
  if [ "$?" != 0 ]; then
      echo "brew not installed properly, exiting"
      exit 123
  fi
else
  MACOS=false
  if lsb_release -i | grep -q -i amazonami
  then
    UPDATE="yum list updates"
    INSTALL="sudo yum -y install"
  else
    DISTRO_NAME=$(cat /etc/os-release | grep ^ID= | cut -d= -f 2 | sed s/'"'//g)
    DISTRO_VERSION=$(cat /etc/os-release | grep ^VERSION_ID= | cut -d= -f 2 | sed s/'"'//g)
    UPDATE="sudo apt-get update"
    INSTALL="sudo DEBIAN_FRONTEND=noninteractive apt-get --no-install-recommends -y --force-yes -q install"
  fi
fi

if [ "$MACOS" = true ] && [ "$SHELL" = "/bin/zsh" ]; then
  PROFILE=~/.zprofile
else
  if [ ! -e ~/.bash_profile -a -e ~/.profile ]; then
    PROFILE=~/.profile
  else
    PROFILE=~/.bash_profile
  fi
fi

brew_update() {
  brew update
  BREW_OUTDATED_PACKAGES=$(brew outdated --quiet || true)
  BREW_UPDATED_PACKAGES=""
}

# accepts <package1> [package2 [package3 [...]]]
brew_install_or_update_packages() {
  set +x
  local package
  for package in "$@"; do
    brew_install_or_update_package_with_args "$package"
  done
  set -x
}


# accepts <package> [args...]
brew_install_or_update_package_with_args() {
  local package="$1"
  shift
  # `brew outdated --quiet` shows `go` instead of `golang` as package name
  # here we simply check for `go` instead of `golang`, other steps remains the same
  local check_outdate_package="$package"
  if [ "$package" = "golang" ]; then
      check_outdate_package="go"
  fi
  if ! brew ls --versions "$package" > /dev/null; then
      # not installed:
      echo "Installing missing brew package $package"
      brew install "$package" "$@"
    elif echo "$BREW_OUTDATED_PACKAGES" | grep -q "\\b${check_outdate_package}\\b" &&
        ! echo "$BREW_UPDATED_PACKAGES" | grep -q "\\b${check_outdate_package}\\b"; then
      # installed and outdated: update and record
      echo "Upgrading outdated brew package $package"
      if brew upgrade "$package" "$@"; then
        # record success
        BREW_UPDATED_PACKAGES="${BREW_UPDATED_PACKAGES} ${package}"
      fi
    else
      echo "Brew package ${package} is already up to date; Skipping"
    fi
}

brew_cask_install_or_update_packages() {
  set +x
  local package
  for package in "$@"; do
    brew_cask_install_or_update_package_with_args "$package"
  done
  set -x
}

brew_cask_install_or_update_package_with_args() {
  local package="$1"
  shift

  brew cask install "$package" "$@"
}

# If installing system side things then let's update the package manager once at the top here to build
# quic
if [ "$DO_MACHINE_INSTALL" = "true" ]; then
  $UPDATE
fi

append_new_line () {

  if [ "$INJENKINS" = true ]; then
      echo "Not adding this $1 new line to $2 when INJENKINS is true"
      echo "Note: INJENKINS is set in scripts/jenkins/buld_common.sh to indicate that we are running tests in jenkins."
      echo "Something is wrong if it is set outwide of jenkins."
      return
  fi

  local newline="$1"
  local filename="$2"
  local sudo="$3"

  # if there is no new line feed at the end of the file, add it
  # otherwise it may end up with syntax error in files like ~/.bash_profile
  if ! diff <(tail -c1 "$filename") <(echo "a new line feed" | tail -c1) &>/dev/null
  then
    if [ "$sudo" = "no" ]; then
      echo "" >> "$filename"
    else
      echo "" | sudo tee -a "$filename"
    fi
  fi

  if [ "$sudo" = "no" ]; then
    echo -e "$newline" >> "$filename"
  else
    echo -e "$newline" | sudo tee -a "$filename"
  fi
}

append_new_line_if_not_exist () {

  local newline="$1"
  local filename="$2"
  local pattern="${3-${newline}}"
  local sudo="${4-no}"

  if ! grep -q "$pattern" "$filename" &>/dev/null
  then
    append_new_line "$newline" "$filename" "$sudo"
  fi
}

source_profile () {
    if [ "$INJENKINS" = true ]; then
	  echo "Not re-sourcing the profile in jenkins."
	  echo "Make sure you update scripts/jenkins/build_common.sh to have your environment."
    else
      . $PROFILE
    fi
}

machine_install () {
  # Run this stanza when doing per-machine setup.  Otherwise, the script will only perform
  # per-user setup.
  export DO_MACHINE_INSTALL=true
}

install_package () {
  if [ "$DO_MACHINE_INSTALL" = "true" ]; then
    $INSTALL "$@"
  else
    echo "skipping machine install for $@"
  fi
}

cask_install_package () {
  if [ "$DO_MACHINE_INSTALL" = "true" ]; then
    $CASK_INSTALL "$@"
  else
    echo "skipping machine install for $@"
  fi
}

update_limits () {
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi
  append_new_line_if_not_exist "* soft nofile 65536" /etc/security/limits.conf "soft nofile 65536" "yes"
  append_new_line_if_not_exist "* hard nofile 65536" /etc/security/limits.conf "hard nofile 65536" "yes"
  append_new_line_if_not_exist "fs.file-max = 1000000"  /etc/sysctl.conf "fs.file-max = 1000000" "yes"
  # for webhdfs we use alot of tcp connections, so boost up multiple
  # settings here, from this article:
  # https://stackoverflow.com/questions/410616/increasing-the-maximum-number-of-tcp-ip-connections-in-linux
  append_new_line_if_not_exist "net.core.somaxconn = 1024" /etc/sysctl.conf "net.core.somaxconn = 1024" "yes"
  append_new_line_if_not_exist "net.ipv4.tcp_tw_reuse=1" /etc/sysctl.conf "net.ipv4.tcp_tw_reuse=1" "yes"
  # these two let more than 500 outbound connections per second.
  append_new_line_if_not_exist "net.ipv4.ip_local_port_range=15000 61000" /etc/sysctl.conf "net.ipv4.ip_local_port_range=15000 61000" "yes"
  append_new_line_if_not_exist "net.ipv4.tcp_fin_timeout=30" /etc/sysctl.conf "net.ipv4.tcp_fin_timeout=30" "yes"
  append_new_line_if_not_exist "net.core.netdev_max_backlog=2000" /etc/sysctl.conf "net.core.netdev_max_backlog=2000" "yes"
  append_new_line_if_not_exist "net.ipv4.tcp_max_syn_backlog=2048" /etc/sysctl.conf "net.ipv4.tcp_max_syn_backlog=2048" "yes"

  #echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers

  if [ "$MACOS" = true ]; then
    echo "Not changing apt settings on OSX"
  else
    # Don't install the recommended packages
    append_new_line_if_not_exist 'APT::Install-Recommends "false";' /etc/apt/apt.conf.d/99_norecommends 'APT::Install-Recommends "false";' 'yes'
    append_new_line_if_not_exist 'APT::AutoRemove::RecommendsImportant "false";' /etc/apt/apt.conf.d/99_norecommends 'APT::AutoRemove::RecommendsImportant "false";' 'yes'
    append_new_line_if_not_exist 'APT::AutoRemove::SuggestsImportant "false";' /etc/apt/apt.conf.d/99_norecommends 'APT::AutoRemove::SuggestsImportant "false";' 'yes'
    # Make apt-get update run in parallel.
    append_new_line_if_not_exist 'APT::Acquire::Queue-Mode "access";' /etc/apt/apt.conf.d/99_norecommends 'APT::Acquire::Queue-Mode "access";' 'yes'
    append_new_line_if_not_exist 'APT::Acquire::Retries 3;' /etc/apt/apt.conf.d/99_norecommends 'APT::Acquire::Retries 3;' 'yes'

   # Use mirrors to speed up downloads of apt-get packages. Note this will overwrite the entire
   # /etc/apt/sources.list file so you might need to add-apt-repository again.
   if [ ! -f /etc/apt/sources.list.bak ]; then
     sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
   fi
   # Clear out old apt list files.
   sudo rm /var/lib/apt/lists/* -vf || true

   # echo "deb mirror://mirrors.ubuntu.com/mirrors.txt trusty main restricted universe multiverse
   #       deb mirror://mirrors.ubuntu.com/mirrors.txt trusty-updates main restricted universe multiverse
   #       deb mirror://mirrors.ubuntu.com/mirrors.txt trusty-backports main restricted universe multiverse
   #       deb mirror://mirrors.ubuntu.com/mirrors.txt trusty-security main restricted universe multiverse" | \
   #   sudo tee /etc/apt/sources.list
   sudo cat /etc/apt/sources.list
   sudo apt-get update
  fi
}

install_python () {
  # Get the latest version of system wide pythong
  # Make sure you run bootstrap_machine to get latest apt-get and software-properties-common
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi
  if [ "$MACOS" = true ]; then
    echo "On OSX we hope that Apple updated python for us."
    install_package pyenv
    pyenv install --skip-existing $LATEST_PYTHON37
    pyenv global $LATEST_PYTHON37
    pyenv version
  else
    install_package software-properties-common # for ppa
    sudo add-apt-repository ppa:deadsnakes/ppa
    sudo apt-get update -y
    sudo apt-get install -y -q --reinstall python3.7
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.7 10
    # This fixes some issue with apt not liking the new python3.7 install and complaining about not
    # having apt_pkg module.
    sudo ln -s /usr/lib/python3/dist-packages/apt_pkg.cpython-35m-x86_64-linux-gnu.so /usr/lib/python3/dist-packages/apt_pkg.cpython-37m-x86_64-linux-gnu.so
    sudo apt-get install -y -q python3-setuptools
    curl -sS https://bootstrap.pypa.io/get-pip.py | sudo python
  fi
}

install_emacs () {
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi
  if [ "$MACOS" = true ]; then
    cask_install_package emacs
  else
    sudo add-apt-repository ppa:kelleyk/emacs && $UPDATE
    install_package emacs26
  fi
}

install_microk8s () {
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi

  if [ "$MACOS" = true ]; then
    echo "MicroK8S is not avaialble on Linux"
    return
  fi

  # install microk8s
  # https://microk8s.io/docs/
  sudo snap install microk8s --classic --channel=1.17/stable
  sudo usermod -a -G microk8s $USER
}

# setup microk8s
setup_microk8s () {
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi

  sudo microk8s.status --wait-ready
  # enable networking and storage
  sudo microk8s.enable dns storage

  # the reason we need this is if we set alias kubectl='microk8s.kubectl'
  # the alias will not be available in the shell script
  # and would cause lots of failures with the lack of the proper alias
  cat <<ENDOFFILE | sudo tee /usr/local/bin/kubectl &>/dev/null
#!/bin/bash

microk8s.kubectl "\$@"
ENDOFFILE
  sudo chmod +x /usr/local/bin/kubectl

  # enable podpreset
  append_new_line_if_not_exist "--runtime-config=settings.k8s.io/v1alpha1=true" /var/snap/microk8s/current/args/kube-apiserver "--runtime-config=settings.k8s.io/v1alpha1=true" "yes"
  append_new_line_if_not_exist "--enable-admission-plugins=PodPreset" /var/snap/microk8s/current/args/kube-apiserver "--enable-admission-plugins=PodPreset" "yes"

  sudo systemctl restart snap.microk8s.daemon-apiserver
}



setup_basic_python () {
  DEFAULT_PYTHON_VERSION=3.7.6
  # Setup python stuff for the machine.
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi

  git clone https://github.com/pyenv/pyenv.git $HOME/.pyenv
  append_new_line_if_not_exist "export PYENV_ROOT=$HOME/.pyenv" $PROFILE "export PYENV_ROOT="
  append_new_line_if_not_exist 'export PATH=$PYENV_ROOT/bin:$PATH' $PROFILE 'export PATH=$PYENV_ROOT'
  append_new_line_if_not_exist 'if command -v pyenv 1>/dev/null 2>&1; then\n  eval "$(pyenv init -)"\nfi' $PROFILE 'if command -v pyenv 1>/dev/null 2>&1; then\n  eval "$(pyenv init -)"\nfi'
  . $PROFILE
  eval "$(pyenv init -)"
  pyenv install --skip-existing $DEFAULT_PYTHON_VERSION
  pyenv global $DEFAULT_PYTHON_VERSION
  pyenv global

  if [ "$MACOS" != true ]; then
    echo "Installing pip..."
    wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py
    sudo python /tmp/get-pip.py
    # if you want to uninstall get-pip.py, use `sudo python -m pip uninstall pip setuptools`
    # if pip isn't installed right, use `sudo apt-get install -y --reinstall python-pip``

    SUDO="sudo"
  fi
    
  $SUDO pip install pip --upgrade
  $SUDO pip install virtualenv
}

git_clone() {
  local repo="$1"
  local local_path="$2"

  git clone git@github.com:$repo $local_path && chown -R $USER $local_path
}

nuke_virtualenv () {
  #anisble's virtual env installation is somehow incompatible with install.sh
  rm -rf ${VIRTUALENV_ROOT}
}

setup_virtualenv () {
  # Setup for the current user the basic pythong virtualenv.
  if [ ! -d "$VIRTUALENV_ROOT/$VE_ENV" ]; then
    echo "mkdir $VIRTUALENV_ROOT"
    mkdir -p $VIRTUALENV_ROOT
    cd $VIRTUALENV_ROOT
    virtualenv --python=python3.7 $VE_ENV
    # Add this to the .bashrc as well so we always start in this env.
    # NOTE: bashrc is only read by interactive shells, so in particular fab
    # won't see this unless you use a fab.prefix.
    if ( ! grep -q '$VIRTUALENV_ROOT/$VE_ENV/bin/activate' $PROFILE ); then
      ASCRON=${ASCRON:-false}
      if [ $ASCRON = "true" ]; then
	# Running in jenkins
	echo "Not adding $VIRTUALENV_ROOT/$VE_ENV since ASCRON=true (jenkins)"
      else
        append_new_line_if_not_exist "\n\n. $VIRTUALENV_ROOT/$VE_ENV/bin/activate" $PROFILE
      fi
    fi
  else
    echo "$VIRTUALENV_ROOT/$VE_ENV directory exists so not setting up virtualenv"
  fi
  echo "Activating virtualenv: $VIRTUALENV_ROOT/$VE_ENV/bin/activate
Note that this only happens within the function script it's called in unfortuantely.
"
  echo ". $VIRTUALENV_ROOT/$VE_ENV/bin/activate"
  . $VIRTUALENV_ROOT/$VE_ENV/bin/activate

  # Now make sure the pip within the virtualenv is the latest one.
  echo "python -m pip install --upgrade pip"
  python -m pip install --upgrade pip
}

activate_virtualenv () {
  echo "Activating virtualenv: $VIRTUALENV_ROOT/$VE_ENV/bin/activate
Note that this only happens within the function script it's called in unfortuantely.
"
  . $VIRTUALENV_ROOT/$VE_ENV/bin/activate
}

setup_docker () {
  # needs more work for OSX
  # This would be nice too to setup development environment:
  # http://hharnisc.github.io/2015/09/16/developing-inside-docker-containers-with-osx.html
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi
  DOCKER_INSTALL=${DOCKER_INSTALL:-false}
  if [ "$DOCKER_INSTALL" = "true" ]; then
    echo "Not installing docker inside of docker"
    return
  fi

  if [ "$MACOS" = true ]; then
    if [  ! docker info > /dev/null ]; then
      echo Install docker by following the Docker Primer:
      open https://docs.docker.com/docker-for-mac/install/
    fi
  else
    # Get a specific version:
    # https://forums.docker.com/t/how-can-i-install-a-specific-version-of-the-docker-engine/1993
    #sudo echo "deb https://get.docker.io/ubuntu docker main" | sudo tee -a /etc/apt/sources.list.d/docker.list
    #install_package lxc-docker-1.9.1

    # This allows for updating to specific docker version.
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce=17.09.0~ce-0~ubuntu --allow-downgrades

    # Get the latest version:
    # wget -qO- https://get.docker.com/ | sh

    # to avoid these errors you need cgroups:
    # 23:22:59 Error response from daemon: oci runtime error: container_linux.go:247: starting container process caused "process_linux.go:258: applying cgroup configuration for process caused \"mountpoint for devices not found\""
    install_package cgroupfs-mount

  fi
}

setup_docker_squash () {
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi
  DOCKER_INSTALL=${DOCKER_INSTALL:-false}
  if [ "$DOCKER_INSTALL" = "true" ]; then
    echo "Not installing docker inside of docker"
    return
  fi
  cd $PACKAGE_ROOT
  wget -nv https://github.com/jwilder/docker-squash/releases/download/v0.2.0/docker-squash-linux-amd64-v0.2.0.tar.gz
  sudo tar -C /usr/local/bin -xzvf docker-squash-linux-amd64-v0.2.0.tar.gz
  sudo rm -rf docker-squash-linux-amd64-v0.2.0.tar.gz
}

setup_docker_user () {
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi
  DOCKER_INSTALL=${DOCKER_INSTALL:-false}
  if [ "$DOCKER_INSTALL" = "true" ]; then
    echo "Not installing docker inside of docker"
    return
  fi
  # Have to add each user to the group.
  if [ -e "/usr/bin/docker" ]; then
    echo "Adding $USER to docker group"
    sudo usermod -aG docker $USER
  else
    echo "/usr/bin/docker does not exist so not adding $USER to docker group"
  fi
}

setup_postgres_client() {
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi
  # If you just need pqsl or pg_restore for example use this.
  if [ "$MACOS" = "true" ]; then
    echo "postgresql-client should never be needed on osx"
    exit 1
  else
    if [ "${DISTRO_NAME}" == "ubuntu" ] && [ "${DISTRO_VERSION}" == "16.04" ]; then
      echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main" | sudo tee -a /etc/apt/sources.list.d/pgdg.list
    elif [ "${DISTRO_NAME}" == "ubuntu" ] && [ "${DISTRO_VERSION}" == "18.04" ]; then
      echo "deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main" | sudo tee -a /etc/apt/sources.list.d/pgdg.list
      install_package gnupg2
    fi
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    sudo apt update
    install_package postgresql-client-10
  fi
}

setup_psycopg2() {
  # Installs just the postgres client.
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi

  # mysql_config needed to install the python mysql package
  if [ "$MACOS" = "true" ]; then
    install_package postgresql
    echo "Note: Instructions to start postgres at startup were just printed..."
  else
    install_package libpq-dev
  fi
}

setup_proto_go() {
  # If you have Go already installed, then get the go compiler too!
  if [ -e "/usr/local/bin/go" -o -e "/usr/local/go" ];  then
    go get -u github.com/golang/protobuf/{proto,protoc-gen-go}
  fi
  which protoc-gen-swagger || {
    go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger
  }
  which protoc-gen-grpc-gateway || {
      go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway
  }

}

install_go() {
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi

  if $MACOS; then
    install_package golang
  else
    GODOWNLOAD=go1.13.4.linux-amd64.tar.gz
    cd $PACKAGE_ROOT
    wget -nv https://dl.google.com/go/$GODOWNLOAD
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf $GODOWNLOAD
    rm -rf $GODOWNLOAD
    # Add links so everyone has access to bo in their normal /usr/local/bin folder.
    sudo ln -f -s /usr/local/go/bin/go /usr/local/bin/go
    sudo ln -f -s /usr/local/go/bin/godoc /usr/local/bin/godoc
    sudo ln -f -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  fi
}

setup_go() {
  # Make sure these are always setup for you account.
  append_new_line_if_not_exist "export GOPATH=\$HOME/go" $PROFILE "export GOPATH="
  append_new_line_if_not_exist "export PATH=\$PATH:\$GOPATH/bin" $PROFILE "export PATH=.*GOPATH"
  append_new_line_if_not_exist "export GO15VENDOREXPERIMENT=1" $PROFILE
  append_new_line_if_not_exist "export AWS_REGION=\"us-east-1\"" $PROFILE

  source_profile
}

setup_jq() {
  # get the jq tool for looking at json.
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi
  install_package jq
}

setup_nc() {
  # get the jq tool for looking at json.
  if [ "$DO_MACHINE_INSTALL" = false ]; then
    return
  fi
  install_package netcat
}

copy_config_files () {
  # Copy standard config files into the user's home dir.
  # Accept one arguemnt optionally to specifcy where to copy them to.

  if $MACOS; then
    echo "Not copying the config files to your home dir on OSX."
  else
    CONFIG_DEST_DIR=${1:-${HOME}/}
    if [ -e "$SCRIPT_DIR/scripts/amazon/config/${USER}" ]; then
      cp -r $SCRIPT_DIR/scripts/amazon/config/${USER}/. $CONFIG_DEST_DIR || true
    fi
  fi
}

setup_emacs(){
  if [ ! -e "$HOME/.emacs.d" ]; then
    /bin/echo "Checking out emacs.d github repo..."
    #ssh-agent $(ssh-add ~/.ssh/id_rsa; git clone git@github.com:JeckyOH/emacs.d.git $HOME/.emacs.d && chown -R $USER $HOME/.emacs.d)
    git_clone JeckyOH/emacs.d.git $HOME/.emacs.d
  fi
}

setup_bash() {
  if [ ! -e "$HOME/.bash_it" ]; then
    /bin/echo "Checking out bash-it GitHub repo..."
    git_clone Bash-it/bash-it.git $HOME/.bash_it
  fi
  $HOME/.bash_it/install.sh 

  # use bobby_v2 as theme, which is a custom theme.
  cp -rf $SCRIPT_DIR/bash_it/custom/* $HOME/.bash_it/custom/ 
  sed -i -e 's/BASH_IT_THEME=.*/BASH_IT_THEME="bobby_v2"/' $HOME/.bash_profile

  append_new_line_if_not_exist "# Just show minimum git info, speed up prompts" $PROFILE "export SCM_GIT_SHOW_MINIMAL_INFO="
  append_new_line_if_not_exist "export SCM_GIT_SHOW_MINIMAL_INFO=true" $PROFILE "export SCM_GIT_SHOW_MINIMAL_INFO="

  append_new_line_if_not_exist "# Disable clock char, very ugly!" $PROFILE "export THEME_SHOW_CLOCK_CHAR="
  append_new_line_if_not_exist "export THEME_SHOW_CLOCK_CHAR=false" $PROFILE "export THEME_SHOW_CLOCK_CHAR="
  
  # for Mac
  osascript -e 'tell app "Terminal"
    do script "bash-it enable alias emacs git osx tmux && \
               bash-it enable completion git git_flow brew kubectl tmux && \
               bash-it enable plugin autojump battery git "
  end tell'
  
  # [TODO] for ubuntu, please start another window to enable bash-it.

  # remove bash deprecation warning.
  append_new_line_if_not_exist "\nexport BASH_SILENCE_DEPRECATION_WARNING=1" $PROFILE "export BASH_SILENCE_DEPRECATION_WARNING="

  # source .bashrc in .bash_profile
  if [ -e "$HOME/.bashrc" ] && [ ! grep -q ".bashrc" ~/.bash_profile ]; then
    append_new_line_if_not_exist "\nif [ -f .bashrc ]; then source .bashrc; fi" $PROFILE "source .bashrc"
  fi
}

# Main.
if [ $# -eq 0 ]; then
  setup_bash
  install_emacs && setup_emacs
  install_go && setup_go
else
  for func in "$@"
  do
      echo "=============================================================================="
      echo "starting install_amazon.sh $func with DO_MACHINE_INSTALL=$DO_MACHINE_INSTALL"
      echo "=============================================================================="
      $func
      echo "=============================================================================="
      echo "finished install_amazon.sh: $func with DO_MACHINE_INSTALL=$DO_MACHINE_INSTALL"
      echo "=============================================================================="
  done
fi

cd $PACKAGE_ROOT
echo "Cleaning up $PACKAGE_ROOT other than the $PACKAGE_ROOT/local dir"
find . -maxdepth 1 -not -name local -not -name . -exec \rm -rf {} \;
echo "Cleaning done."
cd -
