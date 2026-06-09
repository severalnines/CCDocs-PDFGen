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