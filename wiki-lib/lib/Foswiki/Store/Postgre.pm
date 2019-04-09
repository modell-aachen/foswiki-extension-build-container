# See bottom of file for default license and copyright information
package Foswiki::Store::Postgre;

use strict;
use warnings;

use Foswiki::Store ();
our @ISA = ('Foswiki::Store');

use Assert;
use Error qw(:try);

sub new {
  my $class = shift;
  my $this  = $class->SUPER::new(@_);
  return $this;
}

sub finish {
  my $this = shift;
  $this->SUPER::finish();
}

=begin TML

---++ ObjectMethod readTopic($topicObject, $version) -> ($rev, $isLatest)
   * =$topicObject= - Foswiki::Meta object
   * =$version= - revision identifier, or undef
Reads the given version of a topic, and populates the =$topicObject=.
If the =$version= is =undef=, or there is no revision numbered =$version=, then
reads the most recent version.

Returns the version identifier of the topic that was actually read. If
the topic does not exist in the store, then =$rev= is =undef=. =$isLatest=
will  be set to true if the version loaded (or not loaded) is the
latest available version.

Note: Implementations of this method *must* call
=Foswiki::Meta::setLoadStatus($rev, $isLatest)=
to set the load status of the meta object.

=cut

# Implement Foswiki::Store
sub readTopic {
  my ($this, $meta, $version) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod moveAttachment($oldTopicObject, $oldAttachment, $newTopicObject, $newAttachment)
   * =$oldTopicObject, $oldAttachment= - spec of attachment to move
   * $newTopicObject, $newAttachment= - where to move to
Move an attachment from one topic to another.

The caller to this routine should check that all topics are valid, and
access is permitted. $oldAttachment and $newAttachment must be given and
may not be perl false.

=cut

# Implement Foswiki::Store
sub moveAttachment {
  my ($this, $oldTopicObject, $oldAtt, $newTopicObject, $newAtt, $cUID) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod copyAttachment($oldTopicObject, $oldAttachment, $newTopicObject, $newAttachment)
   * =$oldTopicObject, $oldAttachment= - spec of attachment to copy
   * $newTopicObject, $newAttachment= - where to move to
Copy an attachment from one topic to another.

The caller to this routine should check that all topics are valid, and
access is permitted. $oldAttachment and $newAttachment must be given and
may not be perl false.

=cut

# Implement Foswiki::Store
sub copyAttachment {
  my ($this, $oldTopicObject, $oldAtt, $newTopicObject, $newAtt, $cUID) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod attachmentExists($topicObject, $att) -> $boolean

Determine if the attachment already exists on the given topic

=cut

# Implement Foswiki::Store
sub attachmentExists {
  my ($this, $meta, $att) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod moveTopic($oldTopicObject, $newTopicObject, $cUID)

All parameters must be defined and must be untainted.

Implementation must invoke 'update' on event listeners.

=cut

# Implement Foswiki::Store
sub moveTopic {
  my ($this, $oldTopicObject, $newTopicObject, $cUID) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod moveWeb($oldWebObject, $newWebObject, $cUID)

Move a web.

Implementation must invoke 'update' on event listeners.

=cut

# Implement Foswiki::Store
sub moveWeb {
  my ($this, $oldWebObject, $newWebObject, $cUID) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod testAttachment($topicObject, $attachment, $test) -> $value

Performs a type test on the given attachment file.
    * =$attachment= - name of the attachment to test e.g =lolcat.gif=
    * =$test= - the test to perform e.g. ='r'=

The return value is the value that would be returned by the standard
perl file operations, as indicated by $type

    * r File is readable by current user
    * w File is writable by current user
    * e File exists.
    * z File has zero size.
    * s File has nonzero size (returns size).
    * T File is an ASCII text file (heuristic guess).
    * B File is a "binary" file (opposite of T).
    * M Last modification time (epoch seconds).
    * A Last access time (epoch seconds).

Note that all these types should behave as the equivalent standard perl
operator behaves, except M and A which are independent of the script start
time (see perldoc -f -X for more information)

Other standard Perl file tests may also be supported on some store
implementations, but cannot be relied on.

Errors will be signalled by an Error::Simple exception.

=cut

# Implement Foswiki::Store
sub testAttachment {
  my ($this, $meta, $att, $test) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod openAttachment($topicObject, $attachment, $mode, %opts) -> $text

Opens a stream onto the attachment. This method is primarily to
support virtual file systems, and as such access controls are *not*
checked, plugin handlers are *not* called, and it does *not* update the
meta-data in the topicObject.

=$mode= can be '&lt;', '&gt;' or '&gt;&gt;' for read, write, and append
respectively. %

=%opts= can take different settings depending on =$mode=.
   * =$mode='&lt;'=
      * =version= - revision of the object to open e.g. =version => 6=
   * =$mode='&gt;'= or ='&gt;&gt;'
      * no options
Errors will be signalled by an =Error= exception.

=cut

# Implement Foswiki::Store
sub openAttachment {
  my ($this, $meta, $att, $mode, @opts) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod getRevisionHistory ($topicObject [, $attachment]) -> $iterator
   * =$topicObject= - Foswiki::Meta for the topic
   * =$attachment= - name of an attachment (optional)
Get an iterator over the list of revisions of the object. The iterator returns
the revision identifiers (which will usually be numbers) starting with the most
recent revision.

MUST WORK FOR ATTACHMENTS AS WELL AS TOPICS

If the object does not exist, returns an empty iterator ($iterator->hasNext() will be
false).

=cut

# Implement Foswiki::Store
sub getRevisionHistory {
  my ($this, $meta, $attachment) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod getNextRevision ($topicObject) -> $revision
   * =$topicObject= - Foswiki::Meta for the topic
Get the ientifier for the next revision of the topic. That is, the identifier
for the revision that we will create when we next save.

=cut

# Implement Foswiki::Store
sub getNextRevision {
  my ($this, $meta) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod getRevisionDiff ($topicObject, $rev2, $contextLines) -> \@diffArray

Get difference between two versions of the same topic. The differences are
computed over the embedded store form.

Return reference to an array of differences
   * =$topicObject= - topic, first revision loaded
   * =$rev2= - second revision
   * =$contextLines= - number of lines of context required

Each difference is of the form [ $type, $right, $left ] where
| *type* | *Means* |
| =+= | Added |
| =-= | Deleted |
| =c= | Changed |
| =u= | Unchanged |
| =l= | Line Number |

=cut

# Implement Foswiki::Store
sub getRevisionDiff {
  my ($this, $meta, $rev2, $contextLines) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod getVersionInfo($topicObject, $rev, $attachment) -> \%info

Get revision info for a topic or attachment.
   * =$topicObject= Topic object, required
   * =$rev= revision number. If 0, undef, or out-of-range, will get info
     about the most recent revision.
   * =$attachment= (optional) attachment filename; undef for a topic
Return %info with at least:
| date | in epochSec |
| user | user *object* |
| version | the revision number |
| comment | comment in the store system, may or may not be the same as the comment in embedded meta-data |

If =$attachment= and =$rev= are both given, then =$rev= applies to the
attachment, not the topic.

=cut

# Implement Foswiki::Store
sub getVersionInfo {
  my ($this, $meta, $rev, $attachment) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod saveAttachment($topicObject, $attachment, $stream, $cUID, \%options) -> $revNum
Save a new revision of an attachment, the content of which will come
from an input stream =$stream=.
   * =$topicObject= - Foswiki::Meta for the topic
   * =$attachment= - name of the attachment
   * =$stream= - input stream delivering attachment data
   * =$cUID= - user doing the save
   * =\%options= - Ref to hash of options
=\%options= may include:
   * =forcedate= - force the revision date to be this (epoch secs) *X* =forcedate= must be equal to or later than the date of the most recent revision already stored for the topic.
   * =minor= - True if this is a minor change (used in log)
   * =comment= - a comment associated with the save
Returns the number of the revision saved.

Note: =\%options= was added in Foswiki 2.0

=cut

# Implement Foswiki::Store
sub saveAttachment {
  my ($this, $meta, $name, $stream, $cUID, $options) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod saveTopic($topicObject, $cUID, $options) -> $integer

Save a topic or attachment _without_ invoking plugin handlers.
   * =$topicObject= - Foswiki::Meta for the topic
   * =$cUID= - cUID of user doing the saving
   * =$options= - Ref to hash of options
=$options= may include:
   * =forcenewrevision= - force a new revision even if one isn't needed
   * =forcedate= - force the revision date to be this (epoch secs)
    *X* =forcedate= must be equal to or later than the date of the most
    recent revision already stored for the topic.
   * =minor= - True if this is a minor change (used in log)
   * =comment= - a comment associated with the save

Returns the new revision identifier.

Implementation must invoke 'update' on event listeners.

=cut

# Implement Foswiki::Store
sub saveTopic {
  my ($this, $meta, $cUID, $options) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod repRev($topicObject, $cUID, %options) -> $rev
   * =$topicObject= - Foswiki::Meta topic object
Replace last (top) revision of a topic with different content. The different
content is taken from the content currently loaded in $topicObject.

Parameters and return value as saveTopic, except
   * =%options= - as for saveTopic, with the extra options:
      * =operation= - set to the name of the operation performing the save.
        This is used only in the log, and is normally =cmd= or =save=. It
        defaults to =save=.

Used to try to avoid the deposition of 'unecessary' revisions, for example
where a user quickly goes back and fixes a spelling error.

Also provided as a means for administrators to rewrite history (forcedate).

It is up to the store implementation if this is different
to a normal save or not.

Returns the id of the latest revision.

Implementation must invoke 'update' on event listeners.

=cut

# Implement Foswiki::Store
sub repRev {
  my ($this, $meta, $cUID, %options) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod delRev($topicObject, $cUID) -> $rev
   * =$topicObject= - Foswiki::Meta topic object
   * =$cUID= - cUID of user doing the deleting

Parameters and return value as saveTopic.

Provided as a means for administrators to rewrite history.

Delete last entry in repository, restoring the previous
revision.

It is up to the store implementation whether this actually
does delete a revision or not; some implementations will
simply promote the previous revision up to the head.

Implementation must invoke 'update' on event listeners.

=cut

# Implement Foswiki::Store
sub delRev {
  my ($this, $meta, $cUID) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod atomicLockInfo($topicObject) -> ($cUID, $time)
If there is a lock on the topic, return it.

=cut

# Implement Foswiki::Store
sub atomicLockInfo {
  my ($this, $meta) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod atomicLock($topicObject, $cUID)

   * =$topicObject= - Foswiki::Meta topic object
   * =$cUID= cUID of user doing the locking
Grab a topic lock on the given topic.

=cut

# Implement Foswiki::Store
sub atomicLock {
  my ($this, $topicObject, $cUID) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod atomicUnlock($topicObject)

   * =$topicObject= - Foswiki::Meta topic object
Release the topic lock on the given topic. A topic lock will cause other
processes that also try to claim a lock to block. It is important to
release a topic lock after a guard section is complete. This should
normally be done in a 'finally' block. See man Error for more info.

Topic locks are used to make store operations atomic. They are
_note_ the locks used when a topic is edited; those are Leases
(see =getLease=)

=cut

# Implement Foswiki::Store
sub atomicUnlock {
  my ($this, $meta, $cUID) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod webExists($web) -> $boolean

Test if web exists
   * =$web= - Web name, required, e.g. ='Sandbox'=

=cut

# Implement Foswiki::Store
sub webExists {
  my ($this, $web) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod topicExists($web, $topic) -> $boolean

Test if topic exists
   * =$web= - Web name, optional, e.g. ='Main'=
   * =$topic= - Topic name, required, e.g. ='TokyoOffice'=, or ="Main.TokyoOffice"=

=cut

# Implement Foswiki::Store
sub topicExists {
  my ($this, $web, $topic) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod getApproxRevTime ($web, $topic) -> $epochSecs

Get an approximate rev time for the latest rev of the topic. This method
is used to optimise searching. Needs to be as fast as possible.

=cut

# Implement Foswiki::Store
sub getApproxRevTime {
  my ($this, $web, $topic) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod eachChange($meta, $time) -> $iterator

Get an iterator over the list of all the changes between
=$time= and now. $time is a time in seconds since 1st Jan 1970, and is not
guaranteed to return any changes that occurred before (now -
{Store}{RememberChangesFor}). Changes are returned in most-recent-first
order.

=$meta= may be a web or a topic. If it's a web, then all changes for all
topics within that web will be iterated. If it's a topic, only changes
for that topic (since the topic name was first used) will be iterated.
Each change is returned as a reference to a hash containing the fields
documented for =recordChange()=.

Store implementors should note that if compatibility with Foswiki < 2 is
required, the following additional fields must be returned:
   * =topic= - name of the topic the change occurred to
   * =user= - wikiname of the changing user
   * =more= - formatted string indicating if the change was minor or not

=cut

# Implement Foswiki::Store
sub eachChange {
  my ($this, $web, $time) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod recordChange(%args)
Record that the store item changed, and who changed it, and why

   * =verb= - the action - one of
      * =update= - a web, topic or attachment has been modified
      * =insert= - a web, topic or attachment is being inserted
      * =remove= - a topic or attachment is being removed
   * =cuid= - who is making the change
   * =revision= - the revision of the topic that the change appears in
   * =path= - canonical web.topic path for the affected object
   * =attachment= - attachment name (optional)
   * =oldpath= - canonical web.topic path for the origin of a move/rename
   * =oldattachment= - origin of move
   * =minor= - boolean true if this change is flagged as minor
   * =comment= - descriptive text

=cut

# Implement Foswiki::Store
sub recordChange {
  my ($this, %args) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod eachAttachment($topicObject) -> \$iterator

Return an iterator over the list of attachments stored for the given
topic. This will get a list of the attachments actually stored for the
topic, which may be a longer list than the list that comes from the
topic meta-data, which only lists the attachments that are normally
visible to the user.

The iterator iterates over attachment names.

=cut

# Implement Foswiki::Store
sub eachAttachment {
  my ($this, $meta) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod eachTopic($webObject) -> $iterator

Get list of all topics in a web as an iterator

=cut

# Implement Foswiki::Store
sub eachTopic {
  my ($this, $meta) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod eachWeb($webObject, $all) -> $iterator

Return an iterator over each subweb. If $all is set, will return a list of all
web names *under* $web. The iterator returns web pathnames relative to $web.

The list of web names is sorted alphabetically by full path name e.g.
   * AWeb
   * AWeb/SubWeb
   * AWeb/XWeb
   * BWeb

=cut

# Implement Foswiki::Store
sub eachWeb {
  my ($this, $meta, $all) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod remove($cUID, $om, $attachment)
   * =$cUID= who is doing the removing
   * =$om= - thing being removed (web or topic)
   * =$attachment= - optional attachment being removed

Destroy a thing, utterly.

Implementation must invoke 'remove' on event listeners.

=cut

# Implement Foswiki::Store
sub remove {
  my ($this, $cUID, $meta, $attachment) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod query($query, $inputTopicSet, $session, \%options) -> $outputTopicSet

Search for data in the store (not web based).
   * =$query= either a =Foswiki::Search::Node= or a =Foswiki::Query::Node=.
   * =$inputTopicSet= is a reference to an iterator containing a list
     of topic paths. If set to undef, the search/query algo will
     create a new iterator using eachWeb()/eachTopic()
     and the topic and excludetopics options

Returns a =Foswiki::Search::InfoCache= iterator

=cut

# Implement Foswiki::Store
sub query {
  my ($this, $query, $inputTopicSet, $session, $options) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod getRevisionAtTime($topicObject, $time) -> $rev

   * =$topicObject= - topic
   * =$time= - time (in epoch secs) for the rev

Get the revision identifier of a topic at a specific time.
Returns a single-digit rev number or undef if it couldn't be determined
(either because the topic isn't that old, or there was a problem)

=cut

# Implement Foswiki::Store
sub getRevisionAtTime {
  my ($this, $meta, $time) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod getLease($topicObject) -> $lease

   * =$topicObject= - topic

If there is an lease on the topic, return the lease, otherwise undef.
A lease is a block of meta-information about a topic that can be
recovered (this is a hash containing =user=, =taken= and =expires=).
Leases are taken out when a topic is edited. Only one lease
can be active on a topic at a time. Leases are used to warn if
another user is already editing a topic.

=cut

# Implement Foswiki::Store
sub getLease {
  my ($this, $meta) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod setLease($topicObject, $length)

   * =$topicObject= - Foswiki::Meta topic object
Take out an lease on the given topic for this user for $length seconds.

See =getLease= for more details about Leases.

=cut

# Implement Foswiki::Store
sub setLease {
  my ($this, $meta, $lease) = @_;
  die "Not implemented yet!";
}

=begin TML

---++ ObjectMethod removeSpuriousLeases($web)

Remove leases that are not related to a topic. These can get left behind in
some store implementations when a topic is created, but never saved.

=cut

# Implement Foswiki::Store
sub removeSpuriousLeases {
  my ($this, $web) = @_;
  die "Not implemented yet!";
}

1;

__END__
Q.Wiki PostgreContrib - Modell Aachen GmbH

Author: %$AUTHOR%

Copyright (C) 2016 Modell Aachen GmbH

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
