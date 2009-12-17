CREATE TABLE paypal (
    id integer not null primary key,
    invoice integer,
    magic_frob varchar(255),
    status varchar(255)
);
