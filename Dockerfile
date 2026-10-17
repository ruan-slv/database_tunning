# MySQL 8.4 LTS is the target engine for the SQL scripts in this repository.
FROM mysql:8.4

# The source dataset is loaded once when MySQL initializes an empty data volume.
COPY script.sql /docker-entrypoint-initdb.d/01-load-dataset.sql
