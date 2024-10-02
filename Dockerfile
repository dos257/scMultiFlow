FROM ubuntu:22.04
WORKDIR /build



# ------------------------------------------------------------------------------
# continuumio/anaconda3
# Adopted from https://hub.docker.com/layers/continuumio/anaconda3/2024.06-1/images/sha256-4e285050f24d4c5c4d315a61fd9f9f63f9e9cf0ccefc1db7df54e77bdc3ae49d?context=explore
# ------------------------------------------------------------------------------

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PATH=/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ARG INSTALLER_URL_LINUX64=https://repo.anaconda.com/archive/Anaconda3-2024.06-1-Linux-x86_64.sh
ARG SHA256SUM_LINUX64=539bb43d9a52d758d0fdfa1b1b049920ec6f8c6d15ee9fe4a423355fe551a8f7

RUN /bin/sh -c set -x && \
    apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        git \
        libglib2.0-0 \
        libsm6 \
        libgsl-dev \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxinerama1 \
        libxrandr2 \
        libxrender1 \
        mercurial \
        openssh-client \
        procps \
        subversion \
        wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    wget "${INSTALLER_URL_LINUX64}" -O anaconda.sh -q && \
    echo "${SHA256SUM_LINUX64} anaconda.sh" > shasum && \
    sha256sum --check --status shasum && \
    /bin/bash anaconda.sh -b -p /opt/conda && \
    rm anaconda.sh shasum && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc && \
    find /opt/conda/ -follow -type f -name '*.a' -delete && \
    find /opt/conda/ -follow -type f -name '*.js.map' -delete && \
    /opt/conda/bin/conda clean -afy # buildkit



# ------------------------------------------------------------------------------
# quay.io/jupyterhub/jupyterhub
# Adopted from https://github.com/jupyterhub/jupyterhub/blob/main/Dockerfile
# ------------------------------------------------------------------------------

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        patch \
        ca-certificates \
        curl \
        git \
        gnupg \
        locales \
        nodejs \
        npm && \
    locale-gen $LC_ALL && \
    npm install -g configurable-http-proxy@^4.2.0 && \
    rm -rf /var/lib/apt/lists/* /var/log/* /var/tmp/* ~/.npm

RUN pip install jupyterhub==5.1.0

EXPOSE 8000



# ------------------------------------------------------------------------------
# JupyterHub modifications
# ------------------------------------------------------------------------------

RUN apt-get update && \
    apt-get install -y \
        wget \
        curl \
        cmake \
        acl \
        unzip \
        bzip2 \
        htop

RUN pip install \
        notebook \
        nbdime \
        jupyter_contrib_nbextensions \
        virtualenv


# Users creation
# Should be added before RStudio install scripts will add rstudio user with new user ID
ADD users.txt users.txt
RUN xargs -i bash -c "useradd --create-home {} && echo '{}:1' | chpasswd && echo 'cd /data' >>/home/{}/.bashrc" <users.txt
RUN rm users.txt


# JupyterHub configuration
COPY <<EOF /etc/jupyter/jupyter_notebook_config.py
c.NotebookApp.terminado_settings = { "shell_command": ["/bin/bash"] }
EOF

COPY <<EOF /srv/jupyterhub/jupyterhub_config.py
c = get_config()
c.Spawner.notebook_dir = "/data"
c.Authenticator.allow_all = True
EOF

COPY <<EOF /etc/jupyter/labconfig/page_config.json
{
    "disabledExtensions": {
          "@jupyterlab/apputils-extension:announcements": true
    }
}
EOF



# ------------------------------------------------------------------------------
# rocker/rstudio:4.3.3
# Adopted from:
# https://github.com/rocker-org/rocker-versioned2/blob/R4.3.3/dockerfiles/rstudio_4.3.3.Dockerfile
# https://github.com/rocker-org/rocker-versioned2/blob/R4.3.3/dockerfiles/r-ver_4.3.3.Dockerfile
# ------------------------------------------------------------------------------

ENV R_VERSION=4.3.3
ENV R_HOME=/usr/local/lib/R
ENV TZ=Etc/UTC
#ENV CRAN=https://p3m.dev/cran/__linux__/jammy/latest
ENV S6_VERSION=v2.1.0.2
ENV RSTUDIO_VERSION=2023.12.0+369
ENV DEFAULT_USER=rstudio
ENV PANDOC_VERSION=default
ENV QUARTO_VERSION=default

RUN git clone -b R4.3.3 --single-branch https://github.com/rocker-org/rocker-versioned2.git
RUN cp -R ./rocker-versioned2/scripts /rocker_scripts


# https://www.kombitz.com/2024/06/20/how-to-install-r-4-4-1-on-ubuntu-22-04/

RUN apt-get update && \
    apt install -y \
        libxt-dev \
        libcairo2-dev

# icu
RUN wget https://github.com/unicode-org/icu/releases/download/release-73-2/icu4c-73_2-src.tgz && \
    tar xvf icu4c-73_2-src.tgz && \
    cd icu/source && \
    ./configure && \
    make && \
    make install

# iconv
RUN wget https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.16.tar.gz && \
    tar -xvzf libiconv-1.16.tar.gz && \
    cd libiconv-1.16 && \
    ./configure && \
    make && \
    make install


RUN /rocker_scripts/install_R_source.sh
RUN /rocker_scripts/setup_R.sh
RUN /rocker_scripts/install_rstudio.sh
RUN /rocker_scripts/install_pandoc.sh
RUN /rocker_scripts/install_quarto.sh

EXPOSE 8787



# Needed for pip install rpy2
RUN apt-get update && \
    apt-get install -y \
        python3-dev \
        liblzma-dev \
        libbz2-dev \
        libpcre2-dev
RUN pip install \
        rpy2



# ------------------------------------------------------------------------------
# Cellranger arc, cell ranger
# ------------------------------------------------------------------------------

# Accept EULA on pages
# https://www.10xgenomics.com/support/software/cell-ranger-arc/downloads/eula
# https://www.10xgenomics.com/support/software/cell-ranger/downloads/eula
# download files into directory of this Dockerfile
# uncomment following lines to include cellranger into Docker
# result image should not be distributed to third-parties according to EULA

#COPY cellranger-8.0.1.tar.xz cellranger-8.0.1.tar.xz
#COPY cellranger-arc-2.0.2.tar.gz cellranger-arc-2.0.2.tar.gz
#
#RUN echo "5d112b68f8819d50e54a9f3809cf5533 *cellranger-8.0.1.tar.xz" >>md5sum.txt && \
#    echo "7303f8ceee7b60113c9a0087268830cd *cellranger-arc-2.0.2.tar.gz" >>md5sum.txt && \
#    md5sum --check --status md5sum.txt && \
#    cd /opt && \
#    tar -xzvf /build/cellranger-arc-2.0.2.tar.gz && \
#    tar -xvf /build/cellranger-8.0.1.tar.xz && \
#    export PATH=/opt/cellranger-arc-2.0.2:$PATH && \
#    export PATH=/opt/cellranger-8.0.1:$PATH

# For test:
# cellranger-arc testrun --id=tiny
# cellranger testrun --id=check_install



# ------------------------------------------------------------------------------
# Bioinformatics libraries
# Python: Scrublet, MultiQC, ...
# R: Seurat v5, Harmony, scVI, MACS2, Signac, ...
# ------------------------------------------------------------------------------

# Torch has massive dependencies, better to cache
RUN pip install torch


COPY <<EOF bioinformatics.pip.requirements.txt
louvain
doubletdetection
MACS3
multiqc
scrublet
scvi
EOF

RUN pip install --no-cache-dir -r bioinformatics.pip.requirements.txt


RUN apt-get update && \
    apt-get install -y \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
        libhdf5-dev


# https://github.com/hhoeflin/hdf5r/issues/112
# hdf5r may find conda hdf5 instead of system one and will fail with
# unable to load shared object '/usr/local/lib/R/site-library/00LOCK-hdf5r/00new/hdf5r/libs/hdf5r.so'
RUN Rscript -e 'install.packages("hdf5r", configure.args="--with-hdf5=/usr/bin/h5cc")'


COPY <<EOF install.packages.txt
BiocManager
remotes
devtools
tidyverse

ape
data.table
DelayedArray
enrichR
extrafont
ggrastr
harmony
hdf5r
arrow
magmaR
mixtools
quarto
R.utils
Rfast2
rmarkdown
rsvd
SoupX
testthat
tidymodels
VGAM
workflowr
EOF

RUN Rscript -e "packages <- readLines('/build/install.packages.txt'); packages <- packages[packages != '' & !grepl('^#', packages)]; install.packages(packages)"


# 0.2.22 requires R>=4.4.0
RUN Rscript -e "devtools::install_version('rjson', version='0.2.21')"


RUN Rscript -e "BiocManager::install(version = '3.18')"

# packages from multiomics.R and RStudio Dockerfile
COPY <<EOF BiocManager.install.txt

AnnotationDbi
AnnotationFilter
Biobase
BiocGenerics
BiocIO
Biostrings
biovizBase
BPCells
BSgenome
BSgenome.Hsapiens.UCSC.hg19
BSgenome.Hsapiens.UCSC.hg38
BSgenome.Mmusculus.UCSC.mm10
DelayedArray
DESeq2
EnsDb.Hsapiens.v75
EnsDb.Hsapiens.v86
EnsDb.Mmusculus.v79
ensembldb
fastmap
GeneOverlap
GenomeInfoDb
GenomicFeatures
GenomicRanges
ggrepel
ggtree
igraph
IRanges
irlba
lifecycle
limma
MACSr
MAST
Matrix
metap
monocle
presto
Rsamtools
rtracklayer
S4Vectors
Seurat
SeuratObject
Signac
SingleCellExperiment
slingshot
sp
SummarizedExperiment
UCell
WGCNA
XVector

EOF

RUN Rscript -e "packages <- readLines('/build/BiocManager.install.txt'); packages <- packages[packages != '' & !grepl('^#', packages)]; BiocManager::install(packages)"

RUN Rscript -e "remotes::install_github('satijalab/seurat-wrappers', 'seurat5', quiet = TRUE);"
RUN Rscript -e "remotes::install_github('NightingaleHealth/ggforestplot');"
RUN Rscript -e "remotes::install_github('smorabit/hdWGCNA', ref='dev');"
RUN Rscript -e "remotes::install_github('chris-mcginnis-ucsf/DoubletFinder');"


# https://bioconductor.org/packages/release/bioc/html/TFBSTools.html
RUN Rscript -e "BiocManager::install('TFBSTools')"

RUN Rscript -e "remotes::install_github('neurogenomics/MAGMA_Celltyping')"
RUN wget https://vu.data.surfsara.nl/index.php/s/zkKbNeNOZAhFXZB/download -O magma_v1.10.zip
# TODO: unpack, copy to path

# packages and dependencies for SCpubr package
RUN Rscript -e "BiocManager::install('clusterProfiler')"
RUN Rscript -e "BiocManager::install('AUCell')"
RUN Rscript -e "BiocManager::install('enrichplot')"
RUN Rscript -e "BiocManager::install('decoupleR')"
RUN Rscript -e "BiocManager::install('Nebulosa')"

RUN Rscript -e 'install.packages("ggdist")'
RUN Rscript -e 'install.packages("ggExtra")'
RUN Rscript -e 'install.packages("ggrastr")'
RUN Rscript -e 'install.packages("svglite")'
RUN Rscript -e 'install.packages("ggalluvial")'
RUN Rscript -e 'install.packages("ggnewscale")'
RUN Rscript -e "remotes::install_github('saezlab/liana')"
RUN Rscript -e 'install.packages("SCpubr")'

# ------------------------------------------------------------------------------
# scROCK install
# ------------------------------------------------------------------------------

# R dependencies of scrock.datasets
RUN Rscript -e "install.packages('reticulate')"
RUN Rscript -e "remotes::install_github('mojaveazure/seurat-disk');"
RUN Rscript -e "install.packages('scCustomize')"

RUN python -m pip install pip-tools

COPY <<EOF scrock.pip.requirements.txt
numpy # 1.26.4 in Anaconda
scipy # 1.13.1 in Anaconda
torch # not in Anaconda
tqdm # 4.66.4 in Anaconda
scikit-learn # 1.4.2 in Anaconda
matplotlib # 3.8.4 in Anaconda

# for scrock.datasets
pandas # 2.2.2 in Anaconda
hdf5plugin # not in Anaconda
scanpy # not in Anaconda
requests # 2.32.2 in Anaconda

# for tests
scrublet
doubletdetection
EOF

RUN pip install -r scrock.pip.requirements.txt

RUN pip install git+https://github.com/dos257/scrock.git



# ------------------------------------------------------------------------------
# scMoMsQC install
# ------------------------------------------------------------------------------

COPY <<EOF scmomsqc.pip.requirements.txt
numpy # 1.26.4 in Anaconda
pandas # 2.2.2 in Anaconda
plotly # 5.22.0 in Anaconda
scikit-learn # 1.4.2 in Anaconda
statsmodels # 0.14.2 in Anaconda

yattag # not in Anaconda
EOF

RUN pip install -r scmomsqc.pip.requirements.txt

RUN pip install git+https://github.com/dos257/scMoMsQC.git@patch-2



# ------------------------------------------------------------------------------
# Polishing
# ------------------------------------------------------------------------------

RUN apt-get update && \
    apt-get install -y \
        nano

RUN Rscript -e 'devtools::install_github("IRkernel/IRkernel")'
RUN Rscript -e 'IRkernel::installspec(user = FALSE)'
RUN Rscript -e 'devtools::install_github("satijalab/seurat-data")'

RUN apt-get update && \
    apt-get install -y libcairo2-dev
RUN Rscript -e 'remotes::install_github("mojaveazure/seurat-disk");'
RUN Rscript -e "BiocManager::install('Nebulosa')"
RUN Rscript -e 'install.packages("ggrastr")'

# TOFIX: Not mounted yet
#RUN chmod a+w /data

# TODO: remove rm -rf /var/lib/apt/lists/* ; remove /build



# ------------------------------------------------------------------------------
# Run servers
# ------------------------------------------------------------------------------

# Will run jupyterhub
#CMD ["jupyterhub", "-f", "/srv/jupyterhub/jupyterhub_config.py"]

# Will run service rstudio-server start
#CMD ["/init"]

# Will run both
CMD ["/bin/bash", "-c", "service rstudio-server start; jupyterhub -f /srv/jupyterhub/jupyterhub_config.py"]
