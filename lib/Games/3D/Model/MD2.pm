
# Games-3D-Model-MD2 - load/render an .md2 3d model

package Games::3D::Model::MD2;

# (C) by Tels <http://bloodgate.com/>

use strict;

use Exporter;
use Games::3D::Model;
use SDL::OpenGL;
use vars qw/@ISA $VERSION/;
@ISA = qw/Games::3D::Model Exporter/;

$VERSION = '0.03';

##############################################################################
# struct used to load file

my $unpack_header = 
  'a4' .	# ident, equal to IDP2
  'V' .		# version (should be 8)	
  'V' .		# skin width
  'V' .		# skin height
  'V' .		# framesize
  'V' .		# num textures
  'V' .		# num points per frame
  'V' .		# num texture coordinates
  'V' .		# num triangles per frame
  'V' .		# num OpenGL command types
  'V' .		# num frames
  'V' .		# skins offset
  'V' .		# mesh st offset
  'V' .		# triangles offset
  'V' .		# frames offset
  'V' .		# OpenGL cmds offset
  'V' ;		# offset end

# For simplicity reasons, we use the following directly, e.g. no structs or
# objects. This makes conversion to XS code easier.

my $unpack_vector = 'fff'; 			# (x,y,z);
my $unpack_st_index = 'vv'; 			# (s,t);
my $unpack_frame_point = 'CCCC'; 		# (c1,c2,c3,normal);
my $unpack_frame = 'ffffffC16';	
						# (scale_x,scale_y,scale_z,
						#  trans_x, trans_y, trans_z,
						#  name, frame_point) 
my $unpack_mesh = 'vvvvvv';			# mesh_index_x,index_y,index_z,
						# st_index_x, st_index_y,
						# st_index_z

##############################################################################
# methods

sub _init
  {
  # create a new instance of a model
  my $self = shift;

  $self->SUPER::_init(@_);

  $self->{meshes} = [];			# triangles
  $self->{text_coords} = [];		# text coords
  $self->{vertices} = [];		# point list (for each frame the
					# offset into triangles and textures)
  $self->{triangles} = [];		# triangles (mesh and text coord)
					# only one big list
  $self->{textures} = [];		# text coord list (one big list)

  # These are the states for quake 2 models, which might not necc. be right
  # for other models.
                  #     nr, name,  frames, start frame
  $self->{states} = [
    [ 0,  'idle',		40,  0 ],
    [ 1,  'running',	  	 7, 40 ],
    [ 2,  'hurt',	 	14, 47 ],
    [ 3,  'hurt at shoulder',	 6, 61 ],
    [ 4,  'jump',	 	 7, 67 ],
    [ 5,  'idle',	 	22, 74 ],
    [ 6,  'hurt, stumble', 	17, 96 ],
    [ 7,  'idle', 		10, 113 ],
    [ 8,  'idle', 		13, 123 ],
    [ 9,  'crouching', 		19, 136 ],
    [ 10, 'crouching crawl', 	 7, 155 ],
    [ 11, 'idle crouching', 	 8, 162 ],
    [ 12, 'dying kneeling', 	 8, 170 ],
    [ 13, 'dying falling back',	 8, 178 ],
    [ 14, 'dying forward', 	 5, 186 ],
    [ 15, 'dying slowly back', 	 8, 191 ],
    ];  
  }

sub _parse_data
  {
  my ($self,$file) = @_;

  # extract header info
  my ($ident,$version);
  ($ident,$version,
    $self->{skin_width},
    $self->{skin_height},
    $self->{frame_size}, 
    $self->{num_textures},
    $self->{num_points}, 
    $self->{num_text_coords},
    $self->{num_triangles}, 
    $self->{num_opengl_cmd_types},
    $self->{num_frames}, 
    $self->{offset_skins},
    $self->{offset_text_coords}, 
    $self->{offset_triangles}, 
    $self->{offset_frames}, 
    $self->{offset_opengl_cmds}, 
    $self->{offset_end})
  = unpack ($unpack_header,$file);

  die ("File $file seems not to be a .md2 file") if $ident ne 'IDP2';

  my $frame_ofs = $self->{offset_frames};
  for (my $i = 0; $i < $self->{num_frames}; $i++)
    {
    die ("frame_size $self->{frame_size} != ", 40 + 4 * $self->{num_points}) 
     if $self->{frame_size}  != 4 * $self->{num_points} + 40;

    my $pnt_ofs = $frame_ofs + 40;
    my ($sx, $sy, $sz, $tx, $ty, $tz, $name) =
       unpack ($unpack_frame, substr($file,$frame_ofs, 40));
    $self->{vertices}->[$i] = [];
    for (my $j = 0; $j < $self->{num_points}; $j++)
      {
      my ($cx, $cy, $cz, $normal) =
       unpack ($unpack_frame_point, substr($file,$pnt_ofs, 4));
      push @{$self->{vertices}->[$i]},
         [ $sx * $cx + $tx,
         $sy * $cy + $ty,
         $sz * $cz + $tz ];
      $pnt_ofs += 4;
      }
 
    $frame_ofs += $self->{frame_size};
    }

  # for each texture coord
  my $text_ofs = $self->{offset_text_coords};
  for (my $i = 0; $i < $self->{num_text_coords}; $i++)
    {
    my ($s,$t) = unpack($unpack_st_index, substr($file,$text_ofs,4));
    push @{$self->{text_coords}}, 
      ($s / $self->{skin_width}, $t / $self->{skin_height});
    $text_ofs += 4; 
    # print "$i ($s,$t)\n";
    }
  
  my $mesh_ofs = $self->{offset_triangles};
  # create a mesh (triangle list) for each frme
  for (my $j = 0; $j < $self->{num_triangles}; $j++)
    {
    push @{$self->{triangles}},
        [ unpack ( $unpack_mesh,substr($file,$mesh_ofs,12)) ];
    $mesh_ofs += 12;	 # 6 shorts
    }

  $self;
  }

sub render_frame
  {
  # render one frame from the model, without any interpolation
  my ($self,$frame) = @_;

  $frame = $self->{cur_frame} unless defined $frame;
  $frame %= $self->{num_frames};

  my $v = $self->{vertices}->[$frame];
  srand(3);
  glBegin(GL_TRIANGLES()); my $ofs;
  glColor(@{$self->{color}},$self->{alpha}) if defined $self->{color};
  foreach my $t (@{$self->{triangles}})
    {
    glColor(rand(),rand(),rand(),$self->{alpha})
     unless defined $self->{color}; # random

    $ofs = $v->[$t->[0]]; glVertex(@$ofs);
    $ofs = $v->[$t->[2]]; glVertex(@$ofs);
    $ofs = $v->[$t->[1]]; glVertex(@$ofs);
   
    }
  glEnd();
  }

sub _face_normal
  {
  # cacluate face-normal
  my ($p1,$p2,$p3) = @_;

  my $v = Game::3D::Vector->new(   $p2->[0] - $p1->[0],
                                $p2->[1] - $p1->[1],
                                $p2->[2] - $p1->[2] );
  my $w = Game::3D::Vector->new(   $p3->[0] - $p2->[0],
                                $p3->[1] - $p2->[1],
                                $p3->[2] - $p2->[2] );
  $v->cross($w);
  }

sub _render_morphed_frame
  {
  # render a frame morphed between two frames (percent goes from 0..1)
  my ($self,$frame_1,$frame_2,$percent) = @_;

  $frame_1 %= $self->{num_frames};
  $frame_2 %= $self->{num_frames};

#  print "Going from $frame_1 to $frame_2 (at $percent)\n";

  my $v1 = $self->{vertices}->[$frame_1];
  my $v2 = $self->{vertices}->[$frame_2];
  glColor(@{$self->{color}},$self->{alpha}) if defined $self->{color};
  srand(3);
  glBegin(GL_TRIANGLES()); my ($ofs1,$ofs2);
  foreach my $t (@{$self->{triangles}})
    {
   
    #if ($self->{trace})
    #  {
    #  glColor(1,1,1,0.5);
    #  $ofs1 = $v1->[$t->[0]]; glVertex(@$ofs1);
    #  $ofs1 = $v1->[$t->[2]]; glVertex(@$ofs1);
    #  $ofs1 = $v1->[$t->[1]]; glVertex(@$ofs1);
    #  }

    glColor(rand(),rand(),rand(),$self->{alpha})
      unless defined $self->{color}; # random

    # compute a linear interpolated vertex between frame_1 and frame_2

    for my $i (0,2,1)
      {
      $ofs1 = $v1->[$t->[$i]];
      $ofs2 = $v2->[$t->[$i]];

      glVertex( 
        $ofs1->[0] + $percent * ($ofs2->[0] - $ofs1->[0]) ,
        $ofs1->[1] + $percent * ($ofs2->[1] - $ofs1->[1]),
        $ofs1->[2] + $percent * ($ofs2->[2] - $ofs1->[2]) );
      }
    
    #if ($self->{trace})
    #  {
    #  glColor(1,1,1,0.7);
    #  $ofs1 = $v2->[$t->[0]]; glVertex(@$ofs1);
    #  $ofs1 = $v2->[$t->[2]]; glVertex(@$ofs1);
    #  $ofs1 = $v2->[$t->[1]]; glVertex(@$ofs1);
    #  }
   
    }
  glEnd();
  }

1;

__END__

=pod

=head1 NAME

Games::3D::Model::MD2 - load/render 3D models based on the .md2 file format

=head1 SYNOPSIS

	use Games::3D::Model::MD2;

	my $model = Games::3D::Model::MD2->new( 'ogre.md2' );

	$model->render_frame(0);

=head1 EXPORTS

Exports nothing on default.

=head1 DESCRIPTION

This package let's you load and render (via OpenGL) models based on the popular
.md2 file format.

=head1 METHODS

=over 2

=item new()

	my $model = Games::3D::Model::MD2->new( $filename );

Load a model into memory and return an object reference.

=item render_frame()

	$model->render_frame($frame_num);

Render one frame from the model.

=item frames()

	$model->frames();

Return the number of frames in the model.

=item color()

	$rgb = $model->color();		# [$r,$g, $b ]
	$model->color(1,0.1,0.8);	# set RGB
	$model->color(undef);		# random color (default)

Sets the color, that will be set to render the model. The random color
setting means each triangle will get a random RGB color.

=item alpha()

	$a = $model->alpha();		# $a
	$model->color(0.8);		# set A
	$model->alpha(undef);		# set's it to 1.0 (seems an OpenGL
					# specific set because
					# glColor($r,$g,$b) also sets $a == 1

Sets the alpha value. Only usefull when using blending (e.g. transparency).

=back

See L<Games::3D::Model> for more documentation.

=head1 BUGS

=over 2

=item states

The states are hardcoded and corrospond (probably) to the states for Quake 2
models, which might not necc. be right for other models. There is currently
no way to override the state and frame list.

=back

=head1 AUTHORS

(c) 2003 Tels <http://bloodgate.com/>

=head1 SEE ALSO

L<Games::3D>, L<SDL:App::FPS>, and L<SDL::OpenGL>.

=cut

