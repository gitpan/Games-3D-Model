
# Games-3D-Model - load/render 3d models

package Games::3D::Model;

# (C) by Tels <http://bloodgate.com/>

use strict;

use Exporter;
use SDL::OpenGL;
use vars qw/@ISA $VERSION/;
@ISA = qw/Exporter/;

$VERSION = '0.03';

# private vars

my $vertices = pack "d24",
        -0.5,-0.5,-0.5, 0.5,-0.5,-0.5, 0.5,0.5,-0.5, -0.5,0.5,-0.5, # back
        -0.5,-0.5,0.5,  0.5,-0.5,0.5,  0.5,0.5,0.5,  -0.5,0.5,0.5 ; # front

my $indicies = pack "C24",
	4,5,6,7,	# front
	1,2,6,5,	# right
	0,1,5,4,	# bottom
	0,3,2,1,	# back
	0,4,7,3,	# left
	2,3,7,6;	# top

##############################################################################
# methods


sub new
  {
  # create a new instance of a model
  my $class = shift;

  my $self = { };
  bless $self, $class;
  
  my $args = $_[0];
  $args = { @_ } unless ref $args eq 'HASH';
  $self->{type} = $args->{type} || '';

  if ($self->{type} ne '')
    {
    $class = 'Games::3D::Model::' . $self->{type};
    my $pm = $class; $pm =~ s/::/\//g; $pm .= '.pm';
    require $pm;
    bless $self, $class;				# rebless
    }
  $self->_init($args);
  $self->_read_file($self->{file});
  $self;
  }

sub _read_file
  {
  my ($self,$filename) = @_;

  return if !ref $filename && $filename eq '';          # for tests

  if (ref($filename) eq 'Games::Resource')
    {
    $self->_parse_data($filename->contents());
    }

  # read in entire model
  open my $FILE, $filename or die ("Cannot read file $filename: $!");
  binmode $FILE;
  my ($buffer, $file);
  while (sysread($FILE,$buffer,8192) != 0)
    {
    $file .= $buffer;
    }
  close $FILE;
  $self->_parse_data($file);
  }

sub _parse_data
  {
  my $self = shift;

  }
 
sub _init
  {
  my ($self,$args) = @_;

  $self->{file} = $args->{file} || '';
  $self->{type} = $args->{type} || '';
  $self->{name} = $args->{name} || '';
  $self->{model} = undef;

  $self->{cur_frame} = 1;
  $self->{last_frame} = 0;
  $self->{num_frames} = 1;			# entire model

		#     nr, name,  frames, start frame
  $self->{states} = [ [ 0, 'idle', 1,      0 ] ];

  $self->{state} = 0;				# current
  $self->{next_state} = undef;			# none
  $self->{next_state_delay} = 0;
  $self->{old_state_end} = 0;
  
  $self->{time_warp} = 1;			# morph faster/slower
  $self->{time_per_frame} = 100;			# ms between frames
  
  $self->{last_frame_time} = 0;			# when was last frame

  $self;
  }

sub render_frame
  {
  # render one frame from the model, without any interpolation
  # should be overwritten. This method only renders a white cube
  my ($self,$frame) = @_;

  glPushMatrix();
    glColor(1,1,1,1);
    glScale(120,120,120);
    glTranslate(0,6,-40);
    glDisableClientState(GL_COLOR_ARRAY());
    glEnableClientState(GL_VERTEX_ARRAY());
    glVertexPointer(3,GL_DOUBLE(),0,$vertices);
    glDrawElements(GL_QUADS(), 24, GL_UNSIGNED_BYTE(), $indicies);
  glPopMatrix();

  }

sub frames
  {
  # return number of frames in model all in all
  my $self = shift;

  $self->{num_frames};
  }

sub state
  {
  # Set the current model state. Unless delay is 0, the model will be morphed
  # from the current frame of the current state to the first frame of the new
  # state of that time (in ms)
  # if the new state is not defined, returns the number of the current state
  # in list context, returns (state_number, state_name, frames_in_state)
  my ($self) = shift;

 
  if (@_ == 0)
    {
    return @{$self->{states}->{$self->{state}}} if wantarray;
    return $self->{state};
    } 
  my ($new_state,$current_time, $delay) = @_;

  $self->{next_state_delay} = abs($delay);
  if ($delay == 0)
    {
    $self->{last_frame} = $self->{cur_frame};
    $self->{cur_frame} = $self->{states}->[$new_state]->[3];	# start frame
    $self->{state} = $new_state;
    $self->{next_state} = undef;
    $self->{old_state_end} = $current_time;
    }
  else
    {
    $self->{next_state} = $new_state;
    $self->{next_state_start} = $current_time + $delay;
    }
  }

sub states
  {
  # scalar context: return number of states (idle, die etc) in model
  # list context: return list of different states as names (e.g.
  # ('die', 'idle', 'idle - nose picking') would mean state 0 is named 'die',
  # state 1 'idle' and so on.
  my $self = shift;

  return @{$self->{states}} if wantarray;
  scalar @{$self->{states}};
  }

sub time_warp
  {
  # set/get the model's local time_warp factor
  my $self = shift;

  if (@_ > 0)
    {
    $self->{time_warp} = abs(shift || 1);
    }
  $self->{time_warp};
  }

sub render
  {
  # renders the model morphed between the current frame and the next frame
  # bases on the current time
  my ($self,$current_time,$time_warp) = @_;

  my $percent;

  if (defined $self->{next_state})
    {
    # we are going currently from one frame in old state, to the new state

    $percent = 1 - ($self->{next_state_start} - $current_time)  
      / $self->{next_state_delay};
  
    # print "switching to state, $percent done\n";  
    # but the time for the transition is up?
    if ($percent > 1)
      {
      $self->{state} = $self->{next_state};
      $self->{next_state} = undef;		# transition complete
      my $s = $self->{states}->[$self->{state}];

      $percent = 0;
      $self->{last_frame} = $self->{cur_frame};
      $self->{cur_frame} = 1;
      # confine cur frame to state (last frame is 0, so always in range)
      $s = $self->{states}->[$self->{state}];
      $self->{cur_frame} = 0 if $self->{cur_frame} > $s->[3];
      $self->{next_state} = undef;
      $self->{old_state_end} = $self->{next_state_start};
      }
    }
  else
    {
    # assuming the time progressed forward to $current_time and we started
    # this state at old_state_end, and we make this time per frame:
  
    # in ms for a time_warp of 1.0
    my $time_per_frame = $self->{time_per_frame}
     * ($self->{time_warp} * abs($time_warp || 1));

    # then we progressed so many frames
    my $frame1 = ($current_time - $self->{old_state_end}) / $time_per_frame;

    # now we must interpolate between int($frames) and int($frames) + 1
    $percent = $frame1 - int($frame1);	# 0..1 
    $frame1 = int($frame1);
    my $frame2 = $frame1 + 1;

    my $s = $self->{states}->[$self->{state}];
    # however, both frame numbers must be confined to the current state
    $frame1 = ($frame1 % $s->[2]) + $s->[3];
    $frame2 = ($frame2 % $s->[2]) + $s->[3];

    $self->{last_frame} = $frame1;
    $self->{cur_frame} = $frame2;
    }

  # make percent between 0..1
  $percent = abs($percent);
  $percent = 1 if $percent > 1;

  # print "$percent \n" if ($percent == 0) || $percent == 1;

  $self->_render_morphed_frame( 
    $self->{last_frame}, $self->{cur_frame}, $percent );

  $self;
  }

sub _render_morphed_frame
  {
  # renders a morphed frame between frame FA and frame FB at percent (0..100%)
  # should be overridden by subclasses
  my ($self,$fa,$fb,$percent) = @_;
  
  my $scale = $percent * 20 + 100;

  glPushMatrix();
    glColor($percent,$percent,$percent,1);
    glScale($scale,$scale,$scale);
    #glTranslate(0,0,40);
    glDisableClientState(GL_COLOR_ARRAY());
    glEnableClientState(GL_VERTEX_ARRAY());
    glVertexPointer(3,GL_DOUBLE(),0,$vertices);
    glDrawElements(GL_QUADS(), 24, GL_UNSIGNED_BYTE(), $indicies);
  glPopMatrix();

  }

sub current_frame
  {
  my $self = shift;

  $self->{cur_frame};
  }

sub last_frame
  {
  my $self = shift;

  $self->{last_frame};
  }

sub color
  {
  my $self = shift;

  $self->{color} = shift if @_ > 0;
  $self->{color};
  }

sub alpha
  {
  my $self = shift;

  $self->{alpha} = shift if @_ > 0;
  $self->{alpha};
  }

1;

__END__

=pod

=head1 NAME

Games::3D::Model - load/render 3D models

=head1 SYNOPSIS

	use Games::3D::Model;

	my $model = Games::3D::Model->new( 
          file => 'ogre.md2', type => 'MD2' );

	$model->render_frame(0);

=head1 EXPORTS

Exports nothing on default.

=head1 DESCRIPTION

This package let's you load and render (via OpenGL) 3D models based on 
various file formats (these are realized as subclasses).

=head1 METHODS

=over 2

=item new()

	my $model = Games::3D::Model->new( $args );

Load a model into memory and return an object reference. C<$args> is a hash
ref containing the following keys:

	file		filename of model
	type		'MD2' etc

=item render_frame()

	$model->render_frame($frame_num);

Render one frame from the model.

=item frames()

	$model->frames();

Return the number of frames in the model.

=item time_warp()

	print $model->time_warp();
	$model->time_warp(1);

Set/get the model's local time_warp factor. This factor is used to adjust the
animation speed of the model on top of the speed of the overall timeflow. So
you can make some models run faster and others slower, depending on whatever
information you want.

The default is 1. The factor should be > 0.01 and < 100, although
values between 0.1 and 10 work best.

=item render()

	$model->render($current_time);			# at current time
	$model->render($current_time,$time_warp);	# faster/slower

Renders the a morphed frame of the model, between the current frame and the
next frame bases on the current time. This will loop frame in the current
state, see L<state()> on how to change to the next state.

The optional parameter time_warp will be multiplied with the model's default
time_warp, so you can make different instances of one model (e.g. each guard
in your game) render in a different speed. This avoids the "syncronus" look
of groupds of the same type of models. Values would, f.i. be between 0.9 and
1.10 to make the different guards slower or faster.

=item color()

        $rgb = $model->color();         # [$r,$g, $b ]
        $model->color(1,0.1,0.8);       # set RGB
        $model->color(undef);           # random color (default)

Sets the color, that will be set to render the model. The random color
setting means each triangle will get a random RGB color.

=item alpha()

        $a = $model->alpha();           # $a
        $model->color(0.8);             # set A
        $model->alpha(undef);           # set's it to 1.0 (seems an OpenGL
                                        # specific set because
                                        # glColor($r,$g,$b) also sets $a == 1

Sets the alpha value. Only usefull when using blending (e.g. transparency).

=item current_frame()

	$frame = $model->current_frame();

Returns the index number of the current frame.

=item last_frame()

	$frame = $model->last_frame();

Returns the index number of the last rendered frame.

=back

=head1 KNOWN BUGS

=over 2

=item *

Currently the model is loaded as soon as the object is constructed. In some
cases however it might be better to do a delayed loading of models, like
when the player never sees a certain model because it is in a far-away spot of
the level for a long time. This can be fixed in each subclass.

=back

=head1 AUTHORS

(c) 2003 Tels <http://bloodgate.com/>

=head1 SEE ALSO

L<Games::3D>, L<SDL:App::FPS>, and L<SDL::OpenGL>.

=cut

