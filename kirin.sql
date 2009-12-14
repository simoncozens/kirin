CREATE TABLE user ( id integer primary key not null,
    username varchar(50) NOT NULL, 
    password varchar(40) NOT NULL, 
    customer integer 
);

CREATE TABLE customer ( id integer primary key not null, 
    forename char(40) ,
    surname char(40) ,
    org char(80) ,
    address char(80) ,
    town char(80) ,
    county char(80) ,
    country char(2) ,
    postcode char(10) ,
    phone char(20) ,
    fax char(20) ,
    email char(128) ,
    actype char(30) ,
    status /*enum('ok','new','suspended','banned','renew') */,
    dob date ,
    billing_email char(128) ,
    sms char(20) ,
    accountscode char(10) 
); 


CREATE TABLE acl ( 
    id integer primary key not null, 
    user integer, 
    domain integer, 
    action varchar(255), 
    yesno integer 
);

CREATE TABLE admin ( id integer primary key not null, user integer, customer integer);
CREATE TABLE invoice (id integer primary key not null,
    customer integer,
    issued boolean,
    issuedate date,
    paid boolean
);
CREATE TABLE invoicelineitem (
    id integer primary key not null,
    invoice integer,
    description varchar(255),
    cost decimal(5,2)
);

CREATE TABLE package ( 
    id integer primary key not null, 
    category varchar(255), 
    name varchar(255), 
    description text,
    cost decimal(5,2),
    duration varchar(255)
);

CREATE TABLE package_service (
    id integer primary key not null, 
    package integer,
    service integer
);

CREATE TABLE service (
    id integer primary key not null, 
    name varchar(255), 
    plugin varchar(255), 
    parameter varchar(255)
);

CREATE TABLE subscription (
    id integer primary key not null, 
    customer integer, 
    package integer, 
    expires date
);

/* Some dummy data */

INSERT INTO user    values (1, "root", "$1$qbq/wA6Q$C5p.bx1UbNWIu70p8fh18/", 0); /*test*/
INSERT INTO user    values (2, "simon", "$1$qbq/wA6Q$C5p.bx1UbNWIu70p8fh18/", 1); /*test*/
INSERT INTO admin   values (1, 2, 1);
INSERT INTO acl      values (1, 1, "*", "*", 1);

INSERT INTO customer values (1, "Simon", "Cozens", "NetThink", "Somewhere", 
 "Gloucester", "Glos", "UK", "GL2 0PX", "0500 123456", NULL,
 "simon@simon-cozens.org", "foo", "ok", NULL, NULL, NULL, NULL); 
