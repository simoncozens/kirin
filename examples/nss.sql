CREATE TABLE nss_extra_columns 
    (
        user integer not null primary key,
        shell varchar(255) default "/bin/sh",
        status char(1) NOT NULL default 'N',
        homedir varchar(32) NOT NULL default '/tmp',
        lastchange varchar(50) NOT NULL default '0',
        min int(11) NOT NULL default '0',
        max int(11) NOT NULL default '0',
        warn int(11) NOT NULL default '7',
        inact int(11) NOT NULL default '-1',
        expire int(11) NOT NULL default '-1'
    );


CREATE VIEW nss_user AS 
  SELECT 
    user.id AS user_id,
    username AS user_name,
    customer.forename || " " || customer.surname AS realname,
    shell,
    password,
    status,
    user.id + 1000 AS uid,
    65534 AS gid,
    homedir,
    lastchange,
    min,
    max,
    warn,
    inact,
    expire
  FROM user, customer, nss_extra_columns,
  WHERE user.customer = customer.id
    AND user.id       = nss_extra_columns.user;
