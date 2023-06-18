use v6.d;

unit module Net::Postgres:ver<0.0.3>:auth<zef:leont>;

use Protocol::Postgres;

class Connection {
	has Any:D $!socket is required is built;
	has Protocol::Postgres::Client:D $!client is required is built handles<query query-multiple prepare disconnected add-enum-type add-composite-type add-custom-type terminate get-parameter process-id>;

	method !connect($socket, $user, $database, $password, $typemap --> Connection) {
		my $client = Protocol::Postgres::Client.new(:$typemap);
		my $vow = $client.disconnected.vow;
		$socket.Supply(:bin).act({ $client.incoming-data($^data) }, :done{ $vow.keep(True) }, :quit{ $vow.break($^reason) });
		$client.outbound-data.act({ await $socket.write($^data) }, :done{ $socket.close });

		await $client.startup($user, $database, $password);

		self.bless(:$socket, :$client);
	}

	method connect-tcp(Str :$host = 'localhost', Int :$port = 5432, Str :$user = ~$*USER, Str :$database, Str :$password, Protocol::Postgres::TypeMap :$typemap = Protocol::Postgres::default-typemap, Bool :$tls, :%tls-args --> Promise) {
		IO::Socket::Async.connect($host, $port).then: -> $promise {
			my $socket = await $promise;

			if ($tls) {
				require IO::Socket::Async::SSL;
				my $class = ::('IO::Socket::Async::SSL');
				die Protocol::Postgres::X::Client.new('Could not load IO::Socket::Async::SSL') if $class === Any;
				await $socket.write(Protocol::Postgres::Client.startTls);
				my $wanted = await $socket.Supply(:bin).head;
				die Protocol::Postgres::X::Client.new('TLS rejected') if $wanted ne Blob.new(0x53);
				$socket = await $class.upgrade-client($socket, :$host, |%tls-args);
			}

			self!connect($socket, $user, $database, $password, $typemap);
		}
	}

	method connect-local(IO::Path(Str) :$path = '/var/run/postgresql/'.IO, Int :$port = 5432, Str :$user = ~$*USER, Str :$database, Str :$password, Protocol::Postgres::TypeMap :$typemap = Protocol::Postgres::default-typemap --> Promise) {
		my $filepath = $path.child(".s.PGSQL.$port");
		IO::Socket::Async.connect-path(~$filepath).then: -> $promise {
			my $socket = await $promise;
			self!connect($socket, $user, $database, $password, $typemap);
		}
	}

	method connect(Str :$host = 'localhost', IO::Path(Str) :$path = '/var/run/postgresql/'.IO, Int :$port = 5432, Str :$user = ~$*USER, Str :$database, Str :$password, Protocol::Postgres::TypeMap :$typemap = Protocol::Postgres::default-typemap, Bool :$tls, :%tls-args --> Promise) {
		if $host eq 'localhost' && $path.d && IO::Socket::Async.can('connect-path') {
			self.connect-local(:$path, :$port, :$user, :$database, :$password, :$typemap);
		} else {
			self.connect-tcp(:$host, :$port, :$user, :$database, :$password, :$typemap, :$tls, :%tls-args);
		}
	}

	method new() {
		die "You probably want to use connect instead";
	}

	method listen(Str $channel-name --> Promise) {
		my $supply = $!client.get-channel($channel-name);
		my $query = $!client.query("LISTEN $channel-name");
		$query.then: { await $query; $supply };
	}
}

=begin pod

=head1 Name

Net::Postgres - an asynchronous postgresql client

=head1 Synopsis

=begin code :lang<raku>

use v6.d;
use Net::Postgres;

my $client = await Net::Postgres::Connection.connect(:$host, :$port, :$user, :$password, :$database, :$tls);

my $resultset = await $client.query('SELECT * FROM foo WHERE id = $1', 42);
for $resultset.objects(Foo) -> $foo {
    do-something($foo);
}

=end code

=head1 Description

Net::Postgres is asynchronous implementation of (the client side of) the postgresql protocol based on C<Protocol::Postgres>. It is typically used through the C<Net::Postgres::Connection> class.

=head1 Client

C<Net::Postgres::Client> has the following methods

=head2 connect-tcp(--> Promise)

This creates a promise to a new postgres client. It takes the following named arguments:

=item1 Str :$host = 'localhost'

=item1 Int :$port = 5432

=item1 Str :$user = ~$*USER

=item1 Str :password

=item1 Str :$database

=item1 TypeMap :$typemap = Protocol::Postgres::TypeMap::JSON

=item1 Bool :$tls = False

=item1 :%tls-args = ()

=head2 connect-local(--> Promise)

=item1 IO(Str) :$path = '/var/run/postgresql/'.IO

=item1 Int :$port = 5432

=item1 Str :$user = ~$*USER

=item1 Str :password

=item1 Str :$database

=item1 TypeMap :$typemap = Protocol::Postgres::TypeMap::JSON

=head2 connect(--> Promise)

This takes the same arguments as C<connect-local> and C<connect-tcp>. It will call the former if the C<$host> is localhost and the C<$path> exists, otherwise it will call C<connect-tcp>.

=head2 query($query, @bind-values --> Promise)

This will issue a query with the given bind values, and return a promise to the result.

For fetching queries such as C<SELECT> the result in the promise will be a C<ResultSet> object, for manipulation (e.g. C<INSERT>) and definition (e.g. C<CREATE>) queries it will result a string describing the change (e.g. C<DELETE 3>). For a C<COPY TO> query it will C<Supply> with the data stream, and for C<COPY FROM> it will be a C<Supplier>.

Both the input types and the output types will be typemapped between Raku types and Postgres types using the typemapper.

=head2 query-multiple($query --> Supply[ResultSet])

This will issue a complex query that may contain multiple statements, but can not use bind values. It will return a C<Supply> to the results of each query.

=head2 prepare($query --> Promise[PreparedStatement])

This prepares the query, and returns a Promise to the PreparedStatement object.

=head2 add-enum-type(Str $name, ::Enum --> Promise)

This looks up the C<oid> of postgres enum C<$name>, and adds an appriopriate C<Type> object to the typemap to convert it from/to C<Enum>.

=head2 add-composite-type(Str $name, ::Composite, Bool :$positional --> Promise)

This looks up the C<oid> of the postgres composite type <$name>, and maps it to C<Composite>; if C<$positional> is set it will use positional constructor arguments, otherwise named ones are used.

=head2 add-custom-type(Str $name, ::Custom, &from-string?, &to-string?)

This adds a custom converter from postgres type C<$name> from/to Raku type C<Custom>. By default C<&from-string> will do a coercion, and C<&to-string> will do stringification.

=head2 terminate(--> Nil)

This sends a message to the server to terminate the connection

=head2 listen(Str $channel-name --> Promise[Supply])

This listens to notifications on the given channel. It returns a C<Promise> to a C<Supply> of C<Notification>s.

=head1 ResultSet

A C<Net::Postgres::ResultSet> represents the results of a query, if any. It defines the following methods:

=head2 columns(--> List)

This returns the column names for this resultset.

=head2 rows(--> Supply[List])

This returns a Supply of rows. Each row is a list of values.

=head2 hash-rows(--> Supply[Hash])

This returns a Supply of rows. Each row is a hash with the column names as keys and the row values as values.

=head2 object-rows(::Class, Bool :$positional --> Supply[Class])

This returns a Supply of objects of class C<Class>, each object is constructed form the row hash unless positional is true in which case it's constructed from the row list.

=head2 arrays

This returns a sequence of arrays of results from all rows. This may C<await>.

=head2 array

This returns a single array of results from one row. This may C<await>.

=head2 value

This returns a single value from a single row. This may C<await>.

=head2 hashes

This returns a sequence of hashes of the results from all rows. This may C<await>.

=head2 hash

This returns a single hash of the results from one rows. This may C<await>.

=head2 objects(::Class, Bool :$positional)

This returns a sequence of objects based on all the rows. This may C<await>.

=head2 object(:Class, Bool :$positional)

This returns a single object based on a single row. This may C<await>.

=head1 PreparedStatement

A C<Net::Postgres::PreparedStatement> represents a prepated statement. Its reason of existence is to call C<execute> on it.

=head2 execute(@arguments --> Promise)

This runs the prepared statement, much like the C<query> method would have done and with the same result values.

=head2 close()

This closes the prepared statement.

=head2 columns()

This returns the columns of the result once executed.

=head1 Notification

C<Net::Postgres::Notification> has the following methods:

=head2 sender(--> Int)

This is the process-id of the sender

=head2 message(--> Str)

This is the message of the notification

=head1 Todo

=item1 Persistent connections

=item1 Connection pooling

=head1 Author

Leon Timmermans <fawaka@gmail.com>

=head1 Copyright and License

Copyright 2022 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
