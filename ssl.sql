CREATE TABLE ssl_certificate ( id integer primary key not null,
    customer integer,
    enom_cert_id integer,
    csr text,
    key_file text,
    certificate text,
    cert_status varchar(255)
);
