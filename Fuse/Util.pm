# Utility routines for Fuse
# (c) Reuben Thomas  29/11/2007-27/1/2009
# Based on example code from Fuse package

# N.B. that it's better not to have this file as a module of which
# just certain methods can be overridden, because the FS author should
# be forced to at least consider all the methods.

package Fuse::Util;

require 5.10.0;
# On unpatched Perl 5.8.8 (and possibly others), i386 vs x86-64
# detection is broken, so the wrong syscall number is returned. The
# bug is in asm/unistd.ph, where "0" should be "undef". This is fixed
# in 5.10.0, but I don't know whether it is fixed in 5.8.9, or when
# the bug appeared.

use strict;
use warnings;

use Fuse ':xattr';

BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK);
  $VERSION = 0.01;
  @ISA = qw(Exporter);
  @EXPORT = qw(&debug &err &prepend_root);
}
our @EXPORT_OK;


# Utility routines

# Debug flag
my $debugging = 0;

sub debug {
        print STDERR (shift) . "\n" if $debugging ne 0;
}

sub err {
        my ($err) = @_;
        return $err ? 0 : -$!;
}

our $real_root;

sub prepend_root {
        return $real_root . shift;
}

my $can_syscall = eval {
        require 'syscall.ph'; # for SYS_mknod and SYS_lchown
};


# Methods that fall through to the underlying FS

use POSIX qw(ENOENT ENOSYS);
use Fcntl qw(SEEK_SET);
use File::ExtAttr ':all';
use IO::File;

sub real_getattr {
        debug("real_getattr ");
        my $file = shift;
        my (@stat) = lstat($file);
        return -$! unless @stat;
        return @stat;
}

sub real_readlink {
        debug("real_readlink ");
        return readlink(shift);
}

sub real_getdir {
        debug("real_getdir ");
        my $dir = shift;
        opendir(DIRHANDLE, $dir) or return -$!;
        my (@files) = readdir(DIRHANDLE);
        closedir(DIRHANDLE);
        return (@files, 0);
}

sub real_mknod {
        my ($file, $modes, $dev) = @_;
        return -ENOSYS() if !$can_syscall;
        debug("real_mknod ");
        $! = 0;
        syscall(&SYS_mknod, $file, $modes, $dev);
        return -$! if $! != 0;
        return err($file);
}

sub real_unlink {
        debug("real_unlink ");
        my $file = shift;
        return err(unlink $file);
}

sub real_link {
        debug("real_link ");
        my ($old, $new) = @_;
        return err(link($old, $new));
}

sub real_symlink {
        debug("real_symlink ");
        my ($old, $new) = @_;
        return err(symlink($old, $new));
}

sub real_rename {
        debug("real_rename ");
        my ($old, $new) = @_;
        my $err = rename($old, $new) ? 0 : -ENOENT();
        return $err;
}

sub real_mkdir {
        debug("real_mkdir ");
        my ($dir, $perm) = @_;
        return err(mkdir $dir, $perm);
}

sub real_rmdir {
        debug("real_rmdir ");
        my $dir = shift;
        return err(rmdir $dir);
}

sub real_chown {
        return -ENOSYS() if !$can_syscall;
        debug("real_chown ");
        my $file = shift;
        my ($uid, $gid) = @_;
        # Perl's chown() does not chown symlinks, but their targets
        my $err = syscall(&SYS_lchown, $file, $uid, $gid) ? -$! : 0;
        return $err;
}

sub real_chmod {
        debug("real_chmod ");
        my ($file, $mode) = @_;
        return err(chmod($mode, $file));
}

sub real_utime {
        debug("real_utime ");
        my ($file, $atime, $mtime) = @_;
        return err(utime($atime, $mtime, $file));
}

sub real_open {
        my ($file, $mode) = @_;
        debug("real_open ");
        return -$! unless sysopen(FILE, $file, $mode);
        close(FILE);
        return 0;
}

sub real_read {
        debug("real_read ");
        my ($file, $bufsize, $off) = @_;
        my ($handle) = new IO::File;
        open($handle, $file) or return -$!;
        my ($rv);
        if (seek($handle, $off, SEEK_SET)) {
                read($handle, $rv, $bufsize);
        } else {
                $rv = -$!;
        }
        return $rv;
}

sub real_write {
        debug("real_write ");
        my ($file, $buf, $off) = @_;
        open(FILE, '+<', $file) or return -$!;
        my $rv = seek(FILE, $off, SEEK_SET);
        $rv = print(FILE $buf) if $rv;
        return -$! unless $rv;
        close(FILE);
        return length($buf);
}

sub real_getxattr {
        debug("real_getxattr ");
        my ($file) = shift;
        my ($ns, $attr) = parse_xattr(shift);
        debug("getting $ns, $attr ");
        my $ret = getfattr($file, $attr, {namespace => $ns});
        return $ret if defined($ret);
        return -$!;
}

sub real_statfs {
        debug("real_statfs");
        my $file = shift;
        my ($bsize, $frsize, $blocks, $bfree, $bavail,
            $files, $ffree, $favail, $fsid, $basetype, $flag,
            $namemax, $fstr) = statvfs($real_root) || return -$!;
        return ($namemax, $files, $ffree, $blocks, $bavail, $bsize);
}

sub parse_xattr {
        my $attr = shift;
        $attr =~ m/(?:([^.]+)\.)?(.+)/;
        my $ns = $1 || "user";
        my $name = $2;
        return ($ns, $name);
}

sub real_setxattr {
        debug("real_setxattr ");
        my $file = shift;
        my ($ns, $attr) = parse_xattr(shift);
        my ($val, $flags) = @_; # flags can contain XATTR_CREATE and XATTR_REPLACE
        my %flag_hash;
        $flag_hash{create} = 1 if $flags & XATTR_CREATE();
        $flag_hash{replace} = 1 if $flags & XATTR_REPLACE();
        my $ret = setfattr($file, $attr, $val, \%flag_hash, {namespace => $ns});
        return 0;
}

sub real_listxattr {
        debug("real_listxattr ");
        my $file = shift;
        my @attrs = ();
        foreach my $ns (listfattrns($file)) {
                debug("namespace: $ns ");
                foreach my $attr (listfattr($file, {namespace => $ns})) {
                        push @attrs, "$ns.$attr";
                }
        }
        if ($#attrs >= 0) {
                push @attrs, 0;
        } else {
                push @attrs, -$!;
        }
        return @attrs;
}

sub real_removexattr {
        debug("real_removexattr ");
        my $file = shift;
        my ($ns, $attr) = parse_xattr(shift);
        my $ret = delfattr($file, $attr, {namespace => $ns});
        return 0 if $ret;
        return -1;
}

sub real_truncate {
        debug("real_truncate ");
        my $file = shift;
        return err(truncate($file, shift));
}


1;
