CREATE TABLE user ( id integer primary key not null, username, password);
CREATE TABLE acl ( id integer primary key not null, user integer, domain, action, yesno integer );
CREATE TABLE customer ( id integer primary key not null, name, address ); 
CREATE TABLE domain ( id integer primary key not null, customer integer, domainname );
CREATE TABLE admin ( id integer primary key not null, user integer, customer integer);

/* Some dummy data */

INSERT INTO user    values (1, "root", "$1$qbq/wA6Q$C5p.bx1UbNWIu70p8fh18/"); /*test*/
INSERT INTO acl      values (1, 1, "*", "*", 1);
INSERT INTO customer values (1, "Test Customer", "Japan");
INSERT INTO domain   values (1, 1, "test-customer.org");
INSERT INTO admin    values (1, 1, 1);
