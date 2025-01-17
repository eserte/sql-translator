#!/usr/bin/perl
# vim: set ft=perl:

use strict;
use Test::More;
use SQL::Translator;
use SQL::Translator::Schema::Constants;
use Test::SQL::Translator qw(maybe_plan table_ok);

maybe_plan(undef, 'SQL::Translator::Parser::DBI::PostgreSQL');

my @dsn =
  $ENV{DBICTEST_PG_DSN} ? @ENV{ map { "DBICTEST_PG_$_" } qw/DSN USER PASS/ }
: $ENV{DBI_DSN} ? @ENV{ map { "DBI_$_" } qw/DSN USER PASS/ }
: plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test';

my $dbh = eval {
  DBI->connect(@dsn, {AutoCommit => 1, RaiseError=>1,PrintError => 1} );
};

if (my $err = ($@ || $DBI::err )) {
    chomp $err;
    plan skip_all => "No connection to test db. DBI says '$err'";
}

ok($dbh, "dbh setup correctly");
$dbh->do('SET client_min_messages=WARNING');

my $sql = q[
    drop table if exists sqlt_test2;
    drop table if exists sqlt_test1;
    drop table if exists sqlt_products_1;

    create table sqlt_test1 (
        f_serial serial NOT NULL primary key,
        f_varchar character varying(255),
        f_text text default 'FOO',
        f_to_drop integer,
        f_last text
    );

    comment on table sqlt_test1 is 'this is a comment on the first table';
    comment on column sqlt_test1.f_text is 'this is a comment on a field of the first table';

    create index sqlt_test1_f_last_idx on sqlt_test1 (f_last);

    create table sqlt_test2 (
        f_id integer NOT NULL,
        f_int smallint,
        f_fk1 integer NOT NULL references sqlt_test1 (f_serial),
        primary key (f_id, f_fk1)
    );

    CREATE TABLE sqlt_products_1 (
        product_no integer,
        name text default '['''']',
        price numeric(8,4) default 0.0,
        created_at timestamp without time zone default now()
    );

    -- drop a column, to not have a linear id
    -- When the table t_test1 is created, f_last get id 5 but
    -- after this drop, there is only 4 columns.
    alter table sqlt_test1 drop column f_to_drop;
];

$| = 1;

$dbh->begin_work;
$dbh->do($sql);

my $t = SQL::Translator->new(
  trace => 0,
  parser => 'DBI',
  parser_args => { dbh => $dbh },
);
$t->translate;
my $schema = $t->schema;

isa_ok( $schema, 'SQL::Translator::Schema', 'Schema object' );

ok ($dbh->ping, 'External handle still connected');

my @tables = $schema->get_tables;

my $t1 = $schema->get_table("sqlt_test1");
is( $t1->name, 'sqlt_test1', 'Table sqlt_test1 exists' );
is( $t1->comments, 'this is a comment on the first table', 'First table has a comment');

my @t1_fields = $t1->get_fields;
is( scalar @t1_fields, 4, '4 fields in sqlt_test1' );

my $f1 = shift @t1_fields;
is( $f1->name, 'f_serial', 'First field is "f_serial"' );
is( $f1->data_type, 'integer', 'Field is an integer' );
is( $f1->is_nullable, 0, 'Field cannot be null' );
is( ${$f1->default_value}, "nextval('sqlt_test1_f_serial_seq'::regclass)", 'Default value is nextval()' );
is( $f1->is_primary_key, 1, 'Field is PK' );
#FIXME: not set to auto-increment? maybe we can guess auto-increment behavior by looking at the default_value (i.e. it call function nextval() )
#is( $f1->is_auto_increment, 1, 'Field is auto increment' );

my $f2 = shift @t1_fields;
is( $f2->name, 'f_varchar', 'Second field is "f_varchar"' );
is( $f2->data_type, 'character varying', 'Field is a character varying(255)' );
is( $f2->is_nullable, 1, 'Field can be null' );
is( $f2->size, 255, 'Size is "255"' );
is( $f2->default_value, undef, 'Default value is undefined' );
is( $f2->is_primary_key, 0, 'Field is not PK' );
is( $f2->is_auto_increment, 0, 'Field is not auto increment' );
is( $f2->comments, '', 'There is no comment on the second field');

my $f3 = shift @t1_fields;
is( $f3->name, 'f_text', 'Third field is "f_text"' );
is( $f3->data_type, 'text', 'Field is a text' );
is( $f3->is_nullable, 1, 'Field can be null' );
is( $f3->size, 0, 'Size is 0' );
is( $f3->default_value, 'FOO', 'Default value is "FOO"' );
is( $f3->is_primary_key, 0, 'Field is not PK' );
is( $f3->is_auto_increment, 0, 'Field is not auto increment' );
is( $f3->comments, 'this is a comment on a field of the first table', 'There is a comment on the third field');

my $f4 = shift @t1_fields;
is( $f4->name, 'f_last', 'Fouth field is "f_last"' );
is( $f4->data_type, 'text', 'Field is a text' );
is( $f4->is_nullable, 1, 'Field can be null' );
is( $f4->size, 0, 'Size is 0' );
is( $f4->default_value, undef, 'No default value' );
is( $f4->is_primary_key, 0, 'Field is not PK' );
is( $f4->is_auto_increment, 0, 'Field is not auto increment' );

#TODO: no 'NOT NULL' constraint not set

my $t2 = $schema->get_table("sqlt_test2");
is( $t2->name, 'sqlt_test2', 'Table sqlt_test2 exists' );
is( $t2->comments, undef, 'No comment on table sqlt_test2');

my @t2_fields = $t2->get_fields;
is( scalar @t2_fields, 3, '3 fields in sqlt_test2' );

my $t2_f1 = shift @t2_fields;
is( $t2_f1->name, 'f_id', 'First field is "f_id"' );
is( $t2_f1->data_type, 'integer', 'Field is an integer' );
is( $t2_f1->is_nullable, 0, 'Field cannot be null' );
is( $t2_f1->size, 0, 'Size is "0"' );
is( $t2_f1->default_value, undef, 'Default value is undefined' );
is( $t2_f1->is_primary_key, 1, 'Field is PK' );

my $t2_f2= shift @t2_fields;
is( $t2_f2->name, 'f_int', 'Third field is "f_int"' );
is( $t2_f2->data_type, 'smallint', 'Field is an smallint' );
is( $t2_f2->is_nullable, 1, 'Field can be null' );
is( $t2_f2->size, 0, 'Size is "0"' );
is( $t2_f2->default_value, undef, 'Default value is undefined' );
is( $t2_f2->is_primary_key, 0, 'Field is not PK' );

my $t2_f3 = shift @t2_fields;
is( $t2_f3->name, 'f_fk1', 'Third field is "f_fk1"' );
is( $t2_f3->data_type, 'integer', 'Field is an integer' );
is( $t2_f3->is_nullable, 0, 'Field cannot be null' );
is( $t2_f3->size, 0, 'Size is "0"' );
is( $t2_f3->default_value, undef, 'Default value is undefined' );
is( $t2_f3->is_primary_key, 1, 'Field is PK' );
is( $t2_f3->is_foreign_key, 1, 'Field is a FK' );
my $fk_ref1 = $t2_f3->foreign_key_reference;
isa_ok( $fk_ref1, 'SQL::Translator::Schema::Constraint', 'FK' );
is( $fk_ref1->reference_table, 'sqlt_test1', 'FK is to "sqlt_test1" table' );

my $t3 = $schema->get_table("sqlt_products_1");

my $t3_f2= $t3->get_field('name');
is( $t3_f2->data_type, 'text', 'Second field, type "text"' );
is( $t3_f2->default_value, q{['']}, 'default value is json array of empty string' );

my $t3_f3= $t3->get_field('price');
is( $t3_f3->name, 'price', 'Third field is "price"' );
is( $t3_f3->data_type, 'numeric', 'Third field type "numeric"' );
is_deeply( [$t3_f3->size], [8,4], 'Third field size "(8,4)"' );
is( $t3_f3->default_value, '0.0', 'Third field default "0.0"' );

my $t3_f4= $t3->get_field('created_at');
is( $t3_f4->name, 'created_at', 'fourth field is "created_at"' );
is( $t3_f4->data_type, 'timestamp without time zone', 'type is "timestamp without time zone"' );
is( $t2_f3->size, 0, 'Size is "0"' );
is_deeply( $t3_f4->default_value, \"now()", 'default \\"now()"' );

my @t2_constraints = $t2->get_constraints;
is( scalar @t2_constraints, 1, "One constraint on table" );

my $t2_c1 = shift @t2_constraints;
is( $t2_c1->type, FOREIGN_KEY, "Constraint is a FK" );


$dbh->rollback;
$dbh->disconnect;

done_testing();
