FROM ubuntu:24.04

# Proxy setup
ENV http_proxy="http://proxy-dmz.intel.com:911"
ENV https_proxy="http://proxy-dmz.intel.com:912"
ENV no_proxy="*.intel.com,localhost,10.66.140.4,rest-api-0,rest-api-4,rest-api-1,rest-api-2,rest-api-3,127.0.0.1,172.13.0.2,172.13.0.3,172.13.0.4,172.13.0.5,local-ganache,172.18.0.2"

# Install prerequisites
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    curl \
    git \
    gnupg \
    numactl \
    python3 \
    python3-pip \
    python3-venv \
    wget

# Define Intel and public models
# ENV INTEL_MODELS="bert-large-uncased-whole-word-masking-squad-0001 bert-large-uncased-whole-word-masking-squad-int8-0001"
ENV PUBLIC_MODELS="resnet-50-tf brain-tumor-segmentation-0002 ssd_mobilenet_v1_coco"

# Set OpenVINO version and download URL
ENV OPENVINO_VERSION=2024.6
ENV OPENVINO_TAR_URL=https://storage.openvinotoolkit.org/repositories/openvino/packages/2024.6/linux/l_openvino_toolkit_ubuntu24_2024.6.0.17404.4c0f47d2335_x86_64.tgz
ENV OPENVINO_DIR=/opt/intel/openvino_$OPENVINO_VERSION
ENV VENV_DIR=$OPENVINO_DIR/venv

# Download and extract OpenVINO toolkit
RUN wget $OPENVINO_TAR_URL && \
    mkdir -p $OPENVINO_DIR && \
    tar -xzf l_openvino_toolkit_ubuntu24_2024.6.0.17404.4c0f47d2335_x86_64.tgz --strip-components=1 -C $OPENVINO_DIR

# Source OpenVINO environment script
RUN . $OPENVINO_DIR/setupvars.sh
RUN echo "source $OPENVINO_DIR/setupvars.sh" >> ~/.bashrc

# Build and install OpenVINO samples
RUN cd $OPENVINO_DIR/install_dependencies && \
    ./install_openvino_dependencies.sh -y

RUN cd /opt/intel/openvino_$OPENVINO_VERSION/samples/cpp/ && \
    ./build_samples.sh

# Clone and copy Open Model Zoo the Open Model Zoo repository
RUN git clone https://github.com/openvinotoolkit/open_model_zoo.git
RUN cmake -E copy_directory ./open_model_zoo/ $OPENVINO_DIR/deployment_tools/open_model_zoo/

# Install Open Model Zoo dependencies
RUN cd $OPENVINO_DIR/deployment_tools/open_model_zoo/tools/model_tools && \
    python3 -m venv $VENV_DIR && . $VENV_DIR/bin/activate && \
    python3 -m pip install --upgrade pip setuptools && \
    python3 -m pip install openvino && \
    python3 -m pip install -r requirements.in && \
    cd $OPENVINO_DIR/deployment_tools/open_model_zoo/demos && \
    python3 -m pip install -r requirements.txt

# Download and convert public models
RUN . $OPENVINO_DIR/setupvars.sh
RUN cd $OPENVINO_DIR/deployment_tools/open_model_zoo/tools/model_tools && \
    . $VENV_DIR/bin/activate && \
    for model in $PUBLIC_MODELS; do \
        python3 ./downloader.py --name $model -o /model; \
        python3 ./converter.py --name $model --precisions FP16 -o /model; \
    done

# Set the library path
ENV LD_LIBRARY_PATH=$OPENVINO_DIR/deployment_tools/inference_engine/external/tbb/lib:$OPENVINO_DIR/deployment_tools/inference_engine/lib/intel64:$OPENVINO_DIR/deployment_tools/ngraph/lib:$LD_LIBRARY_PATH

# Set the entry point to the benchmark application
ENTRYPOINT [ "$OPENVINO_DIR/samples/cpp/build/benchmark_app" ]
