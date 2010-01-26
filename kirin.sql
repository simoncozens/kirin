CREATE TABLE user ( id integer primary key not null,
    username varchar(50) NOT NULL unique, 
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
    status varchar(8)/*enum('ok','new','suspended','banned','renew') */,
    dob date ,
    billing_email char(128) ,
    sms char(20) ,
    accountscode char(10) 
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
    subscription integer,
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

CREATE TABLE jobqueue (
    id integer primary key not null, 
    customer integer,
    plugin varchar(255),
    method varchar(255),
    parameters text
);

