import os
import sys
sys.path.insert(0, os.path.abspath("../src"))
sys.path.insert(0, os.path.abspath('..'))

project = "ClusterControl Documentation"
author = "Severalnines"
release = "2.5.0"

extensions = [
    "myst_parser",
    "sphinx_design",
    "sphinx_exercise"
]

source_suffix = {
    ".md": "markdown",
}

myst_enable_extensions = [
    "colon_fence",
    "deflist",
    "tasklist",
    "linkify",
]

myst_allow_file_inclusion = True

myst_heading_anchors = 3

html_theme = "sphinx_book_theme"

latex_engine = "xelatex"

latex_elements = {
    "papersize": "a4paper",
    "pointsize": "11pt",
    "extraclassoptions": "openany,oneside",
    "tableofcontents": r"""
         \clearpage
         \tableofcontents
    """,
    "maketitle": r"""
        \sphinxmaketitle

        \begin{center}
        \textbf{\large Abstract}
        \end{center}

        \noindent
        This is the ClusterControl Reference Manual. It documents ClusterControl
        through version 2.4.0, including installation, configuration, cluster
        deployment, monitoring, and management features.

        \vspace{1em}

        \noindent
        For notes detailing the changes in each release, see the ClusterControl
        Release Notes.

        \vspace{1em}

        \noindent
        For help with using ClusterControl, please visit the Severalnines support
        channels, where you can discuss your issues with other users.

        \vspace{2em}

        \noindent
        Document generated on: \today
    """,
    "preamble": r"""
        \usepackage{fancyhdr}

        % article class: \leftmark = section, \rightmark = subsection.
        \renewcommand{\chaptermark}[1]{\markboth{#1}{}}
        \renewcommand{\sectionmark}[1]{\markright{#1}}

        \pagestyle{fancy}
        \fancyhf{}
        \fancyhead[L]{ClusterControl}
        \fancyhead[R]{\nouppercase{\leftmark}}
        \fancyfoot[L]{\rightmark}
        \fancyfoot[C]{\thepage}
        \renewcommand{\headrulewidth}{0.4pt}
        \renewcommand{\footrulewidth}{0.4pt}

        \fancypagestyle{plain}{%
        \fancyhf{}%
        \fancyhead[L]{ClusterControl Documentation}%
        \fancyhead[R]{\nouppercase{\rightmark}}%
        \fancyfoot[C]{\thepage}%
        \renewcommand{\headrulewidth}{0.4pt}%
        \renewcommand{\footrulewidth}{0pt}%
        }

        \usepackage{newunicodechar}
        \newunicodechar{🡒}{\textrm{→}}

        \usepackage{enumitem}
        \setlistdepth{9}
        \renewlist{itemize}{itemize}{9}
        \setlist[itemize]{label=$\bullet$}
        \renewlist{enumerate}{enumerate}{9}
        \usepackage{newunicodechar}
        \newunicodechar{🡒}{\textrm{→}}
        \newunicodechar{🙏}{} 
    """
}

latex_documents = [
    (
        "index",
        "clustercontrol.tex",
        "ClusterControl Reference Manual",
        "Severalnines",
        "manual",
    ),
]
