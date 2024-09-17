# scMultiFlow

This is the Docker image for Python and R bioinformatics tools. It contains:

* Python 3.12.4, Anaconda 2024-06.1, JupyterHub 5.1.0 (with R kernel)
* R 4.3.3, RStudio 2023.12.0, Bioconductor 3.18, libraries for single-cell analysis, including Seurat 5.1.0.
* cellranger 8.0.1, cellranger-arc-2.0.2 (see Dockerfile how to manually add it, because of EULA)
* [scROCK](https://github.com/dos257/scrock) and [scMoMsQC](https://github.com/Rachmanichou/scMoMsQC) libraries


## Usage

```
docker pull TODO/scmultiflow
docker run --detach -p 18000:8000 -p 18787:8787 \
    --volume "$(realpath ..)/data":/data \
    --name scmultiflow-container TODO/scmultiflow
```

You can access to JupyterHub by http://{docker-ip}:18000/

You can access to RStudio by http://{docker-ip}:18787/

One can change ports in Makefile used for Docker run.


## Users

Both JupyterHub and RStudio use user list containing `user1000`, `user1001`, ..., `user1009` by default, with password "1". It is done for compatibility with external volumes mounted into Docker, containing user notebooks and files. One can edit `users.txt` and rebuild Docker image with `make build` command if they want to change that.


## Build

```
make build
make run
```
