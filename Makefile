build_nocache:
	docker rm scmultiflow-container -f
	docker build --tag scmultiflow --no-cache --progress=plain . 2>&1 | tee build.log

build:
	docker rm scmultiflow-container -f
	docker build --tag scmultiflow . 2>&1 | tee build.log

run:
	docker run --detach -p 18000:8000 -p 18787:8787 \
		--volume "$(realpath ..)/data":/data \
		--name scmultiflow-container scmultiflow

bash:
	docker run -it -p 18000:8000 -p 18787:8787 \
		--volume "$(realpath ..)/data":/data \
		--name scmultiflow-container scmultiflow /bin/bash
