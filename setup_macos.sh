#!/usr/bin/env bash

# This script is to setup the basic working environment for the macOS users

if [ $(uname) != "Darwin" ]; then
  /bin/echo "this script is for macos setup, exiting..."
  exit 1
fi

MIN_SW_VER="10.15.3" # This is macOS Catalina
SW_VER=$((sw_vers -productVersion;echo "$MIN_SW_VER") | sort -V | head -n1)
if [ "$SW_VER" != "$MIN_SW_VER" ]; then
  echo "Please make sure the macOS is upgraded to Catalina first!"
  exit 1
fi

if [ -n "$SUDO_USER" ]; then
  echo "Please re-run the script without sudo."
  exit 1
fi

if [ "${SHELL##*/}" = "zsh" ]; then
  chsh -s /bin/bash
fi

if [ "${SHELL##*/}" = "bash" ]; then
  # somehow the bash on macos does not call .bashrc on user login
  # call .bashrc in .bash_profile
  if [ ! -e ~/.bash_profile ]; then
    touch $HOME/.bash_profile 
  fi
  chown $USER ~/.bash_profile
else
  echo "Only bash are supported currently."
fi

# generate the private keys if necessary
if [ ! -d ~/.ssh ] || [ ! -f ~/.ssh/id_rsa.pub ]; then
  /bin/echo "Generating your ssh private keys..."
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keygen -f ~/.ssh/id_rsa -t rsa -N "" -C "${USER}@${HOSTNAME}"
fi

# check Xcode installation
while ! (pkgutil --pkgs | grep -qi Xcode && which xcode-select &>/dev/null)
do
  /bin/echo "Install Xcode from App Store and press ENTER to continue."
  open "https://itunes.apple.com/us/app/xcode/id497799835?mt=12"
  read
done

# check homebrew installation
if ! which brew &>/dev/null
then
  /bin/echo "Trying to install homebrew..."
  ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

while ! which brew &>/dev/null
do
  /bin/echo "Check http://brew.sh/ to install Homebrew. Enter to continue."
  read
done

# check iterm2 installation
if ! brew cask list iterm2 > /dev/null; then
  echo "Trying to install iterm2..."
  brew cask install iterm2
fi

while ! brew cask list iterm2 > /dev/null
do
  /bin/echo "Check https://www.iterm2.com/downloads.html to install iterm2. Enter to continue"
  read
done


# check git installation
if ! which git &>/dev/null
then
  /bin/echo "Trying to install git..."
  brew install git
fi

while ! which git &>/dev/null
do
  /bin/echo "The auto install somehow failed. Try to install git in another terminal. Enter to continue"
  read
done

# configure git
git_user=$(git config -l | grep user.name | cut -d= -f2)
if [ -z "$git_user" ]; then
  user1="ua"
  user2="ub"
  while [ "$user1" != "$user2" -o "$user1" == "" -o "$user2" == "" ]
  do
    /bin/echo -n "What is your full name? "
    read user1
    /bin/echo -n "Name again? "
    read user2
  done

  git config --global user.name "$user1"
fi

git_email=$(git config -l | grep user.email | cut -d= -f2)
if [ -z "$git_email" ]; then
  email1="ea"
  email2="eb"
  while [ "$email1" != "$email2" -o "$email1" == "" -o "$email2" == "" ]
  do
    /bin/echo -n "What is your GitHub email? "
    read email1
    /bin/echo -n "Email again? "
    read email2
  done

  git config --global user.email "$email1"
fi

git_editor=$(git config -l | grep core.editor | cut -d= -f2)
if [ -z "$git_editor" ]; then
  editor=""
  while [ "$editor" != "vim" -a "$editor" != "emacs" ]
  do
    /bin/echo -n "Do you prefer vim or emacs to be your default git editor? [vim, *emacs] "
    read editor
    if [ -z "$editor" ]; then
      editor="emacs"
    fi
  done

  git config --global core.editor $editor
fi

chown $USER ~/.gitconfig

# github ssh access checking
rt=100
while [ $rt -ne 1 ]
do
  ssh -i ~/.ssh/id_rsa -o "StrictHostKeyChecking no" -T git@github.com
  rt=$?

  if [ $rt -ne 1 ]; then
    /bin/echo "Please configure the github ssh key access from https://github.com/settings/ssh"
    /bin/echo ""
    /bin/echo "Here is your public key you want to paste"
    /bin/echo "---------- DO NOT PASTE THIS LINE --------------"
    cat ~/.ssh/id_rsa.pub
    /bin/echo "---------- DO NOT PASTE THIS LINE --------------"
    open "https://github.com/settings/ssh"

    /bin/echo "press ENTER when ready to continue."
    read
  fi
done
