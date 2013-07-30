#!/usr/bin/perl -w

my $actualpkg = undef;
my $actualversion = "";
my $prefix = "";
my $packagestring = "Package: ";
my $nopackagestring = "Nopackage:";
my $prefixstring = "Installed: ";

my $first = 1;

print "\$[\n";

# quoting all >"< and >\< characters
# bugzilla #220172
sub Quote ($) {
    my $string = shift;
    
    # backslashes are already escaped in the packages_info file
    # $string =~ s/\\/\\\\/g;
    $string =~ s/\"/\\\"/g;

    return $string;
}

while (my $line = <>)
{
    chomp($line);

    # nopackage
    if (substr($line, 0, length($packagestring)) eq $packagestring || $line eq $nopackagestring)
    {
	if ($line ne $nopackagestring)
	{
	    my $full = substr($line, length($packagestring));
	    $full =~ ".*-(.*-.*)";

	    $actualversion = $1;
	    $actualpkg = substr($full, 0, length($full) - length($actualversion) - 1);
	}
	else
	{
	    if (!$first)
	    {
		print "]],\n";
	    }

	    print "\"\" : \$[ \"vers\" : \"\", \"prefix\" : \"\", \"sel_type\" : \" \", \"files\" : [\n";
	}

	$prefix = "";
    }
    # package
    elsif (substr($line, 0, length($prefixstring)) eq $prefixstring)
    {
	$prefix = substr($line, length($prefixstring));

	if ($prefix eq "(none)")
	{
	    $prefix = "";
	}

	if (!$first)
	{
	    print "]],\n";
	}

	$first = 0;

	print "\"". Quote($actualpkg) ."\" : \$[ ".
		"\"vers\" : \"". Quote($actualversion) ."\", ".
		"\"prefix\" : \"". Quote($prefix) ."\", ".
		"\"sel_type\" : \" \", ".
		"\"files\" : [\n";
	
    }
    # file in a package
    elsif (substr($line, 0, 1) eq "/")
    {
	print "\"". Quote($line). "\",\n";
    }
}

if (!$first)
{
    # close file list
    print "]\n";
}

print "]]\n";
