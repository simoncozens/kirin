CREATE TABLE user ( id primary key not null, username, password);
CREATE TABLE acl ( user, domain, action, yesno );
CREATE TABLE customer ( id primary key not null, name, address ); 
CREATE TABLE domain ( id primary key not null, customer, domainname );
CREATE TABLE admin ( id primary key not null, user, customer );

/* Some dummy data */

INSERT INTO user    values (1, "root", "$1$qbq/wA6Q$C5p.bx1UbNWIu70p8fh18/"); /*test*/
INSERT INTO acl      values (1, "*", "*", 1);
INSERT INTO customer values (1, "Test Customer", "Japan");
INSERT INTO domain   values (1, 1, "test-customer.org");
INSERT INTO admin    values (1, 1, 1);
