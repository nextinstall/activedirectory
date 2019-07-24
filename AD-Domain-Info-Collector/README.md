# Collect-ADDomainInfo.ps1

This script should be run to gather data about an Active Directory enviornment. It can assist in planning migrations, or understanding size/scope and topology of an enviornment.

*Script creates artifcats for the following*
* AD Objects - Users, Computers, Groups
* GPOs (takes backup of all accessable/readable GPOs)
* SPNs
* Schema (creates .ldif file)

## Getting Started

Download the script & run it! 

Parameters available:
* Computer Object Last Login (how far back to go). Default: 99999 days
* Specific OS to search for. Default: "*"
* Artifact directory. Default: "C:\CollectedADData"

Script creates a .ZIP file to your artifact directory of all gathered artifacts.


## Prerequisites

Active Directory Module
PowerShell v2 or greater.

## Versioning

v1.0 - Inital Commit!
v1.2 - SPN collection added, LogDir logic and .zip output improved

## Authors

* **Tom Gregory** - *Initial work* - [NextInstall](https://github.com/NextInstall)

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

Harvard University Information Security & the Harvard AD Engineering Team - for paying me to do this!*
