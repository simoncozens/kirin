CREATE TABLE ssl_certificate ( id integer primary key not null,
    customer integer,
    enom_cert_id integer,
    domain varchar(255), /* We could parse the CSR but that's horrid */
    csr text,
    key_file text,
    certificate text,
    cert_status varchar(255)
);
