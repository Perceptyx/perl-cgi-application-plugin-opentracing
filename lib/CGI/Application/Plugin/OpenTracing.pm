package CGI::Application::Plugin::OpenTracing;

use strict;
use warnings;

our $VERSION = '0.01';

use base 'Exporter';

use OpenTracing::Implementation;
use OpenTracing::GlobalTracer;

use Time::HiRes qw( gettimeofday );


our @implementation_import_params;

sub import {
    my $package = shift;
    @implementation_import_params = @_;
    
    my $caller  = caller;
    
    $caller->add_callback( init     => \&init     );
        
    $caller->add_callback( prerun   => \&prerun   );
    
    $caller->add_callback( postrun  => \&postrun  );
    
    $caller->add_callback( teardown => \&teardown );
    
}



sub init {
    my $cgi_app = shift;
    
    my $tracer = _init_opentracing_implementation($cgi_app);
    $cgi_app->{__PLUGINS}{OPENTRACING}{TRACER} = $tracer;

    my $context = $tracer->extract_context;
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_REQUEST} =
        $tracer->start_active_span( 'cgi_request', child_of => $context );
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_REQUEST}
        ->get_span->add_tags(
            'component'             => 'CGI::Application',
            'http.method'           => _cgi_get_http_method($cgi_app),
            'http.status_code'      => '000',
            'http.url'              => _cgi_get_http_url($cgi_app),
        );
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_SETUP} =
        $tracer->start_active_span( 'cgi_setup');
}



sub prerun {
    my $cgi_app = shift;
    
    my $baggage_items = _get_baggage_items($cgi_app);
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_SETUP}
        ->get_span->add_baggage_items( %{$baggage_items} );
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_SETUP}->close;
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_REQUEST}
        ->get_span->add_baggage_items( %{$baggage_items} );
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_REQUEST}
        ->get_span->add_tags(
            'runmode'               => _get_current_runmode($cgi_app),
            'runmethod'             => _cgi_get_run_method($cgi_app),
        );
    
    my $tracer = $cgi_app->{__PLUGINS}{OPENTRACING}{TRACER};
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_RUN} =
        $tracer->start_active_span( 'cgi_run');
    
    return
}



sub postrun {
    my $cgi_app = shift;
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_RUN}->close;
    
    return
}



sub teardown {
    my $cgi_app = shift;
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{CGI_REQUEST}->close;
    
    return
}



sub _init_opentracing_implementation {
    my $cgi_app = shift;
    
    my @implementation_settings = @implementation_import_params;
    
    my $default_span_context = get_default_span_context($cgi_app);
    $cgi_app->{__PLUGINS}{OPENTRACING}{DEFAULT_CONTEXT} = $default_span_context;
    
    push @implementation_settings, (
        default_span_context_args => $default_span_context,
    ) if $default_span_context;
    
    OpenTracing::Implementation
        ->bootstrap_global_tracer( @implementation_settings );
    
    return
}



sub _cgi_get_run_method {
    my $cgi_app = shift;
    
    my $run_mode = $cgi_app->get_current_runmode();
    my $run_methode = { $cgi_app->run_modes }->{ $run_mode };
    
    return $run_methode
}



sub _cgi_get_http_method {
    my $cgi_app = shift;
    
    my $query = $cgi_app->query();
    
    return $query->request_method();
}



sub _cgi_get_http_url {
    my $cgi_app = shift;
    
    my $query = $cgi_app->query();
    
    return $query->url();
}



sub get_opentracing_global_tracer {
    OpenTracing::GlobalTracer->get_global_tracer()
}



sub get_default_span_context {
    my $cgi_app = shift;
    
    my $default_span_context =
        $cgi_app->can('opentracing_default_span_context') ?
            $cgi_app->opentracing_default_span_context( )
            :
            undef
    ;
    
    return $default_span_context
}



sub get_baggage_items {
    my $cgi_app = shift;
    
    my $baggage_items =
        $cgi_app->can('opentracing_baggage_items') ?
            $cgi_app->opentracing_baggage_items( )
            :
            undef # $ENV{OPENTRACING_IMPLEMENTATION}
    ;
    
    return $baggage_items
}



1;
