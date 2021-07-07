![bash_unit CI](https://github.com/pforret/shmixcloud/workflows/bash_unit%20CI/badge.svg)
![Shellcheck CI](https://github.com/pforret/shmixcloud/workflows/Shellcheck%20CI/badge.svg)
![GH Language](https://img.shields.io/github/languages/top/pforret/shmixcloud)
![GH stars](https://img.shields.io/github/stars/pforret/shmixcloud)
![GH tag](https://img.shields.io/github/v/tag/pforret/shmixcloud)
![GH License](https://img.shields.io/github/license/pforret/shmixcloud)
[![basher install](https://img.shields.io/badge/basher-install-white?logo=gnu-bash&style=flat)](https://basher.gitparade.com/package/)

# shmixcloud

![shmixcloud](assets/shmixcloud.jpg)

Download Mixcloud shows to disk to be used in e.g. car

## 🔥 Usage

```
Program: shmixcloud 0.0.1 by peter@forret.com
Updated: 2021-07-07
Description: Download Mixcloud shows to disk to be used in e.g. car
Usage: normal.sh [-h] [-q] [-v] [-f] [-l <log_dir>] [-t <tmp_dir>] <action> <input?>
Flags, options and parameters:
    -h|--help        : [flag] show usage [default: off]
    -q|--quiet       : [flag] no output [default: off]
    -v|--verbose     : [flag] output more [default: off]
    -f|--force       : [flag] do not ask for confirmation (always yes) [default: off]
    -l|--log_dir <?> : [option] folder for log files   [default: /Users/pforret/log/normal]
    -t|--tmp_dir <?> : [option] folder for temp files  [default: .tmp]
    <action>         : [parameter] action to perform: analyze/convert
    <input>          : [parameter] input file/text (optional)
```

## ⚡️ Examples

```bash
$ shmixcloud https://www.mixcloud.com/djsupermarkt_tooslowtd/
$ shmixcloud https://www.mixcloud.com/djsupermarkt_tooslowtd/
```

## 🚀 Installation

with [basher](https://github.com/basherpm/basher)

	$ basher install pforret/shmixcloud

or with `git`

	$ git clone https://github.com/pforret/shmixcloud.git
	$ cd shmixcloud

## 📝 Acknowledgements

* script created with [bashew](https://github.com/pforret/bashew)

&copy; 2021 Peter Forret
