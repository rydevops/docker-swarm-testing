FROM registry.access.redhat.com/ubi7/ubi:7.9

RUN yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    yum install -y postgresql13
    
CMD ["/bin/sleep", "100000"]

