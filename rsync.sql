CREATE TABLE rsync ( id integer primary key not null,
    customer integer,
    login integer,
    password varchar(40) NOT NULL, 
    host varchar(40) NOT NULL, 
    last_used varchar(20)
);
