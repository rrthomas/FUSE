# FUSE

[FUSE](http://fuse.sourceforge.net/) (Filesystem in Userspace) is an excellent way to hack up filesystems on various operating systems (it is supported best on Linux and BSD). The [Fuse](http://search.cpan.org/~DPAVLIN/Fuse/) Perl module lets you write filesystems in Perl. Scary, but attractively easy!

I’ve written an extension, `Fuse::Util`, which provides fall-through methods that can be used to write a FUSE filing system which falls through to the underlying filesystem for some of its methods, and a few filesystems:

=loop_fs=
    A simple loopback filesystem.
=metadata_fs=
    A loopback filesystem which presents the metadata of each file on the underlying filesystem as a file. A design for a more complex version which copes with directories as well is also given in the file @metadata_fs_ideal@.
=filter_attr_fs=
    A filesystem which gives a filtered view of the underlying filesystem according to which objects possess a certain extended attribute. (This could easily be extended to arbitrary predicates.)
=urifs=
    An automounter for the internet. Needs sshfs, curlftpfs and httpfs2, and allows URLs to be used as filenames.

# Download

fuse-bits release 2:

   * Source code (ready to run): $webfile{fuse-bits-2.tar.gz,tar.gz}