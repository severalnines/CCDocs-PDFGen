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
    local version="" arg
    for arg in "$@"; do
        case "$arg" in
            --for-version=*) version="${arg#--for-version=}" ;;
            *) echo "Unknown option: $arg" >&2; return 1 ;;
        esac
    done

    cc_set_manual_env || return 1
    cd "${CC_MAN_SPHINX_DIR}" || return 1

    local rc=0 conf="conf.py" backup=""
    if [ -n "$version" ]; then
        backup="$(mktemp)" && cp "$conf" "$backup" || { cd - >/dev/null; return 1; }
        sed -i.bak -E "s/^release = \".*\"/release = \"${version}\"/" "$conf" && rm -f "${conf}.bak"
    fi

    sphinx-build -b latex -c . src build/pdf && \
    ( cd build/pdf && latexmk -xelatex clustercontrol.tex ) || rc=$?

    # restore the original conf.py, even if the build failed
    if [ -n "$backup" ]; then
        cp "$backup" "$conf" && rm -f "$backup"
    fi

    cd - >/dev/null
    return $rc
}

alias cc_cd_mkdocs='cd ${CC_MKDOCS_DOCS_DIR}/../'
alias cc_cd_sphinx='cd ${CC_MAN_SPHINX_DIR}'
alias cc_cd_gen_tools_dir='cd ${CC_MAN_SPHINX_DIR}/tools/'
alias cc_create_http_server='cd ${CC_MAN_SPHINX_DIR}/build/pdf/; python -m http.server 80'