# Building OpenSTA (Ubuntu 24.04 or WSL)

```
sudo apt-get install -y cmake g++ tcl-dev swig bison flex libeigen3-dev zlib1g-dev autoconf automake libtool
git clone --depth 1 https://github.com/ivmai/cudd
cd cudd && autoreconf -fi && ./configure --prefix=$HOME/cudd && make -j4 && make install && cd ..
git clone --depth 1 https://github.com/parallaxsw/OpenSTA
cd OpenSTA && mkdir build && cd build
cmake .. -DCUDD_DIR=$HOME/cudd -DCMAKE_BUILD_TYPE=Release
make -j4
sudo cp sta /usr/local/bin/
sta -version
```
