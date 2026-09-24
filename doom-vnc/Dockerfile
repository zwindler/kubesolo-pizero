FROM alpine:3.22 AS build
RUN apk add --no-cache build-base cmake curl git linux-headers zlib-dev zlib-static libjpeg-turbo-dev libjpeg-turbo-static

ARG LIBVNC_VERSION=0.9.15
ARG LIBVNC_SHA256=62352c7795e231dfce044beb96156065a05a05c974e5de9e023d688d8ff675d7
RUN curl -fsSL -o /tmp/libvnc.tar.gz https://github.com/LibVNC/libvncserver/archive/refs/tags/LibVNCServer-${LIBVNC_VERSION}.tar.gz \
 && echo "${LIBVNC_SHA256}  /tmp/libvnc.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/libvnc.tar.gz -C /tmp \
 && cmake -S /tmp/libvncserver-LibVNCServer-${LIBVNC_VERSION} -B /tmp/vnc-build -DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_SHARED_LIBS=OFF \
      -DWITH_ZLIB=ON -DWITH_JPEG=ON -DWITH_LZO=OFF -DWITH_PNG=OFF -DWITH_SDL=OFF -DWITH_GTK=OFF -DWITH_LIBSSHTUNNEL=OFF \
      -DWITH_GNUTLS=OFF -DWITH_OPENSSL=OFF -DWITH_GCRYPT=OFF -DWITH_SYSTEMD=OFF -DWITH_FFMPEG=OFF -DWITH_WEBSOCKETS=OFF \
      -DWITH_SASL=OFF -DWITH_XCB=OFF -DWITH_QT=OFF -DWITH_EXAMPLES=OFF -DWITH_TESTS=OFF -DWITH_TIGHTVNC_FILETRANSFER=OFF \
 && cmake --build /tmp/vnc-build -j"$(nproc)" \
 && cmake --install /tmp/vnc-build

ARG DOOMGENERIC_COMMIT=dcb7a8dbc7a16ce3dda29382ac9aae9d77d21284
RUN git clone https://github.com/ozkl/doomgeneric /src \
 && git -C /src checkout ${DOOMGENERIC_COMMIT}

COPY doomgeneric_vnc.c /src/doomgeneric/
COPY doom1.wad /doom1.wad
RUN echo "f0cefca49926d00903cf57551d901abe  /doom1.wad" | md5sum -c -

ARG RESX=320
ARG RESY=200
WORKDIR /src/doomgeneric
RUN SRC="dummy am_map doomdef doomstat dstrings d_event d_items d_iwad d_loop d_main d_mode d_net f_finale f_wipe g_game hu_lib hu_stuff info i_cdmus i_endoom i_joystick i_scale i_sound i_system i_timer memio m_argv m_bbox m_cheat m_config m_controls m_fixed m_menu m_misc m_random p_ceilng p_doors p_enemy p_floor p_inter p_lights p_map p_maputl p_mobj p_plats p_pspr p_saveg p_setup p_sight p_spec p_switch p_telept p_tick p_user r_bsp r_data r_draw r_main r_plane r_segs r_sky r_things sha1 sounds statdump st_lib st_stuff s_sound tables v_video wi_stuff w_checksum w_file w_main w_wad z_zone w_file_stdc i_input i_video doomgeneric doomgeneric_vnc" \
 && gcc -Os -DNORMALUNIX -DLINUX -D_DEFAULT_SOURCE -DDOOMGENERIC_RESX=${RESX} -DDOOMGENERIC_RESY=${RESY} \
      -ffunction-sections -fdata-sections -Wl,--gc-sections -static -s \
      $(for f in $SRC; do echo $f.c; done) -o /doom -lvncserver -ljpeg -lz -lpthread -lm

FROM scratch
COPY --from=build /doom /doom
COPY --from=build /doom1.wad /doom1.wad
EXPOSE 5900
ENTRYPOINT ["/doom", "-iwad", "/doom1.wad"]
