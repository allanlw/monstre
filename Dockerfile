FROM ubuntu:14.04

RUN apt-get update -y && apt-get install -y \
	gcj-jdk \
	cython3 \
	build-essential \
	libpython3-dev \
	ghc \
	libghc-json-dev \
	libghc-pretty-show-dev \
	maven2

COPY ./src /opt

WORKDIR /opt

RUN make -j

ENTRYPOINT ["/opt/monstre"]
