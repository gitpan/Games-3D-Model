#!/usr/bin/perl -w

use Test::More tests => 2;
use strict;

BEGIN
  {
  $| = 1;
  unshift @INC, '../blib/lib';
  unshift @INC, '../blib/arch';
  unshift @INC, '.';
  chdir 't' if -d 't';
  use_ok ('Games::3D::Model::MD2');
  }

can_ok ('Games::3D::Model::MD2', qw/ 
  new render_frame frames _read_file
  _render_morphed_frame render time_warp states state
  color alpha last_frame current_frame
  /);

#my $model = Games::3D::Model::MD2->new ( );
#
#is (ref($model), 'Games::3D::Model::MD2', 'new worked');


