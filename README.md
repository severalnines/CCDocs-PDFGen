# CCDocs-PDFGen
This is the README guide for generating ClusterControl documentation to PDF or CCDocs-PDFGen

## Preparing your environment
During this development, the work is done using `root` OS home user directory. So preferrably use the the `/root` for any development purposes. 

The Linux Distro used for development is **Ubuntu 24.04  LTS (Noble Numbat)**. Preferrably, this shall be the ideal OS to do further work and the documenation is tested and solely done using this Linux flavor.

### Preparing your envionrment requires setup your active working directory for this CC -> PDF generator project.
#### Clone the git repository
```bash 
git clone git@github.com:severalnines/CCDocs-PDFGen.git
```

#### Install python required packages
```bash
apt update
apt install python3.12-venv python3-pip
```

#### Fix python-alternative sym-links
```bash
update-alternatives --install /usr/bin/python python /usr/bin/python3 1
```

#### Prepare your Python virtual environment 
```bash
cd /root/CCDocs-PDFGen
python -m venv venv_ccpdf_doc
source venv_ccpdf_doc/bin/activate
```

## Requirements
After you prepared your environment, you need to install required packages through `pip`. 

### The following packages shall need to be installed to achieve a successful PDF generated documentation or manual.

#### Install required fonts for PDF generted guide
 ```bash
 apt update
 apt install -y fonts-freefont-otf \
  fonts-freefont-ttf \
  imagemagick \
  texlive-latex-recommended \
  texlive-latex-extra \
  texlive-fonts-recommended \
  texlive-xetex \
  latexmk \
  fonts-freefont-ttf \
  fonts-dejavu
```

#### Install required packages for generating PDF and understanding mkdocs using using `pip`. 
The repository has the file `requirements.txt`. So in your environment, this shall be `/root/CCDocs-PDFGen/requirements.txt`. If you open this file, this shall contain the following modules or package names. 
 ```bash
 cat requirements.txt
 ```
 and use the following contents below
```
mkdocs
mkdocs-material
mkdocs-glightbox
mkdocs-autorefs
mike
sphinx
sphinx-design
myst-parser
sphinx-book-theme
linkify-it-py
pyyaml
```
Then run the command below to install it:
```bash
pip install -r requirements.txt
```

#### Install npm required for converting mermaide to image
```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
sudo apt-get install -y nodejs
```
#### CC-Gen-PDF requires a full copy of our ClusterControl documentation repo i.e. [cc-docs](https://github.com/severalnines/cc-docs). This is required to make it work so that you can copy or pull the contents from the ClusterControl documentation. Do a clone and place it to your `/root` as well. 
```bash
cd /root
git clone git@github.com:severalnines/cc-docs.git
```
## Setup your home with shortcut and automated commands necessary for generating PDF
### Create the automation functions/aliases script
#### Create the bin directory,
Create the `/root/bin` directory,
```bash
mkdir /root/bin/
```
##### Then create the file `/root/bin/ccdocs-pdfgen-exports.sh` and copy the contents from file `<path-of-CCDocs-PDFGen-repo>/home_script/exports.sh`. The `exports.sh` file contains shortcuts and functions for automating the generation of PDF script
```bash
#!/bin/sh

export CC_MAN_GEN_DIR="${HOME}/CCDocs-PDFGen"
export CC_MAN_SPHINX_DIR="${CC_MAN_GEN_DIR}/sphinx"
export CC_MKDOCS_DOCS_DIR="${HOME}/cc-docs/docs"
export V_ENV=venv_ccpdf_doc

# Set manual env for mkdocs
cc_set_manual_env() {
    cd "$CC_MAN_GEN_DIR" && source ${V_ENV}/bin/activate
}

# Now cc_gen_pdf can call it directly
cc_gen_pdf() {
    cc_set_manual_env && \
    cd "${CC_MAN_SPHINX_DIR}" && \
    sphinx-build -b latex -c . src build/pdf && \
    cd build/pdf && \
    latexmk -xelatex clustercontrol.tex && \
    cd -
}

alias cc_cd_mkdocs='cd ${CC_MKDOCS_DOCS_DIR}/../'
alias cc_cd_sphinx='cd ${CC_MAN_SPHINX_DIR}'
alias cc_cd_gen_tools_dir='cd ${CC_MAN_SPHINX_DIR}/tools/'
alias cc_create_http_server='cd ${CC_MAN_SPHINX_DIR}/build/pdf/; python -m http.server 80'

```

#### Append the line below to your `/root/.bashrc`,
```bash
cat <<eof >> /root/.bashrc

. \$HOME/bin/ccdocs-pdfgen-exports.sh
eof
```

#### Load the automated functions or aliases
```bash
. ~/.bashrc
```

## Generating the PDF
The whole framework of ClusterControl PDF generator is structured with the following mechanisms:
- Configuration File
- Role scripts
- Logging

### Configuration file
Before you generate the PDF, the CC-Gen-PDF has it's own configuration. Make sure you set it properly. To set this, open the file `$CC_MAN_SPHINX_DIR/tools/config/config.ini`. The following parameters should be set correctly:

#### CC_MKDOCS_YML
This is the full path to the mkdocs.yml nav definition file. Default is set to `/root/cc-docs/mkdocs.yml`

#### CC_MKDOCS_SOURCE_DIR
This is the `/docs` sub-dir of the [cc-docs](https://github.com/severalnines/cc-docs) repository where it contains the *.md files. Defaults to /root/cc-pdf-gen-raw/sphinx/docs

#### CC_SPHINX_SRC_DIR
This is the destination directory. Ideally, this is the sphix/src directory. Defaults to `</root-or-path-to-CCDocs-PDFGen-repo>/sphinx/src/`

#### CC_PDFGEN_IGNORE_FILE
Since in the SOURCE_DIR has directories/files which can be ignored. Place inside these to this ignore file config under conf directory. Default value is `ignore_file_list.txt`

#### CC_PDFGEN_IGNORE_FILE
CC_LOG_FILE=log/pdf_gen.log

### Role scripts
The role scripts are set of tools which are built independently based on its role to get the job done. Below are the scripts and its role together with its path where it can be located.

#### CCDocs-PDFGen/sphinx/tools/bin/gen-order-sections.py
The concept of this role script is to copy the contents of the `</root-or-path-to-cc-docs-repo-parent>/cc-docs/mkdocs.yml` file. This file has the navigation entries which does tells what contents do the CC-Gen-PDF shall have in its context when generated. Then it formats the sections properly that shall be easier to generate indexes and *.md files as resources for sphinx to use or base. This shall generate the ordered sections and save it to `</root-or-path-to-CCDocs-PDFGen-repo>/sphinx/tools/conf/order-sections.yaml`

#### CCDocs-PDFGen/sphinx/tools/bin/copy-docs.py
Parse `</root-or-path-to-cc-docs-repo-parent>/cc-docs/mkdocs.yml` nav section and copy all referenced .md files to a target directory, preserving the directory structure. Basically, it does simply copies the *.md files from source repo i.e. ([cc-docs](https://github.com/severalnines/cc-docs))

#### CCDocs-PDFGen/sphinx/tools/bin/sphinx-index-gen.py
Reads `</root-or-path-to-CCDocs-PDFGen-repo>sphinx/tools/conf/order-sections.yaml` and generates Sphinx index.md files
in `CC_SPHINX_SRC_DIR` for the root and for each top-level section. It is a complex script so make sure to learn and understand how this works. Basically the idea is to be compliant of how formatting works in Sphinx which shall be compatible to generate a PDF for ClusterControl manual.

Simply, the mechanism and concept requires to achieve the following:
- `CC-DOCS/index.md` -> `CC_SPHINX_SRC_DIR/index.md`
    - Simply Uses index_main_template.md.

- Per-section  ->  `CC_SPHINX_SRC_DIR/<section>/index.md`
    - Uses index_sub_template.md.
    \
    {title} = human title derived from the slug.
    \
    {files} = section labels interspersed with Sphinx refs:
        - Section labels kept as-is from YAML with colon appended (hyphens preserved)
        - File paths: hyphens removed, .md stripped (index stays as index)

Example: given the YAML fragment under "getting-started":
  - tutorials:
    - getting-started/tutorials/index.md
    - day-1-operations:
      - your-first-cluster:
        - mysql-mariadb:
          - getting-started/tutorials/.../standalone.md

Output lines written to {files}:
  - tutorials:
    - gettingstarted/tutorials/index
    - day-1-operations:
        - your-first-cluster:
          - mysql-mariadb:
            - gettingstarted/tutorials/.../standalone

For more info, checkout the header of this role script

#### CCDocs-PDFGen/tools/bin/md_to_sphinx.py
Enables the *.md scripts to be fully compatible with sphinx to get the desired output and formatting once the PDF generation starts. It simply discovers and runs all bash helper scripts under `sphinx/tools/helpers/` in
sorted order. Each helper is responsible for converting a specific set of MkDocs tags or syntax that is incompatible with Sphinx/MyST.

Optionally, if you desire to exclude the helper you have in `sphinx/tools/helpers/`, simply do not prefix it with a number so that upon running or scanning of helper scripts, it shall not be read. This is the way how to disable it.

### Logging
The CC-Gen-PDF logs any actions that were taken using the CC-Gen-PDF shall be logged too


## How To Use This and generate a PDF manual
Run the command:
```bash
## Make sure you are in Sphinx directory
$ cc_cd_sphinx
## Prepare the ordered sections
$ python tools/bin/gen-order-sections.py
## Copy the docs from cc-docs to the src repo compatible for sphinx generated pdf
$ python tools/bin/copy-docs.py
## Generate index*.md files for sphinx resource basis
$ python tools/bin/sphinx-index-gen.py
## Run helper scripts to make the sphinx sources compatible and fully generate pdf
$ python tools/bin/md_to_sphinx.py
## Generate the PDF
$ cc_gen_pdf
## Create the web server to view the PDF generated. Make sure to go to http://<hostname>>/clustercontrol.pdf
$ cc_create_http_server
```

### Note: When generating a PDF, make sure you pull the latest ClusterControl documentation repository
```bash
cd /root/cc-docs
git pull 
```
If you need to generate a different version of ClusterControl-based documentation, make sure you change the branch where you want the PDF to be based.

