# pg_dump/pg_restore da mesma versão do servidor + cliente do MinIO.
FROM pgsty/mc:RELEASE.2026-10-26T00-00-00Z AS mc

FROM postgres:17.11-alpine
COPY --from=mc /usr/bin/mc /usr/local/bin/mc
COPY condoguard-backup.sh /usr/local/bin/condoguard-backup
RUN chmod 0755 /usr/local/bin/condoguard-backup
ENTRYPOINT ["/usr/local/bin/condoguard-backup"]
CMD ["backup"]
