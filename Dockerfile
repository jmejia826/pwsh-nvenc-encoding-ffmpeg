# ==== START OF UBUNTU VERSION ====
# Download base image of CentOS7
FROM ubuntu:20.10
# ==== END OF UBUNTU VERSION ====

# ==== START OF NVIDIA ====
FROM nvidia/cuda:10.2-base
# ==== END OF NVIDIA ====

# ==== START OF CONTAINER LABEL ====
# LABEL about this container
LABEL maintainer="jmejia@juanmejia.org"
LABEL version="0.16"
LABEL description="This is a custom Docker container for Powershell, Mediainfo, FFMPEG encoding."
# ==== END OF CONTAINER LABEL ====

# Disable prompt during package installation
ARG DEBIAN_FRONTEND=noninteractive

# Update Ubuntu Software repository
RUN apt update

# ===== START OF MICROSOFT REPOSITORY ====
# Add the Powershell Repository https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7.1
RUN apt install -y wget rsync apt-transport-https software-properties-common

# Download / install / remove debs needed for microsoft and mediainfo
RUN wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb \
            https://mediaarea.net/repo/deb/repo-mediaarea_1.0-16_all.deb
RUN dpkg -i *deb* && rm *deb*

# Update the list and enable universe
RUN apt update && add-apt-repository universe

# ==== START OF INSTALLING APPS ====
RUN apt install -y mediainfo powershell ffmpeg cuda-drivers
# ==== END OF INSTALLING APPS ====

# Environment with some defaults
ENV TEN_BIT_ENCODING=${TEN_BIT_ENCODING:-0} \
    DELETE_SOURCE_FILE=${DELETE_SOURCE_FILE:-0} \
    CONCURRENT_ENCODES=${CONCURRENT_ENCODES:-1} \
    VIDEO_BIT_RATE=${VIDEO_BIT_RATE:-3M} \
    FILTER=${FILTER:-*} \
    SONARR_RENAME=${SONARR_RENAME:-0} \
    RADARR_RENAME=${RADARR_RENAME:-0} \
    MODE=DOCKER

# ==== START OF Copying the latest powershell script to /app ====
RUN mkdir app
COPY ./nvenc_hevc_conversion.ps1 /app/
COPY ./start_app.sh /app/
# ==== END OF Copying the latest powershell script to /app ====

# ==== EXECUTE teh bash ====
WORKDIR /app
RUN chmod +x start_app.sh
ENTRYPOINT ["./start_app.sh"]
