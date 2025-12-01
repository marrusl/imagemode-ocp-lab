FROM configs AS final
RUN dnf install -y tcpdump && \
    bootc container lint
    # NOTE: on 4.18 use `ostree container commit` in place of
    # `bootc container lint`
