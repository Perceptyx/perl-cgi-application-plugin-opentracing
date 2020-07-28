package CGI::Application::Plugin::OpenTracing;

use strict;
use warnings;

our $VERSION = 'v0.102.0';

use syntax 'maybe';

use OpenTracing::Implementation;
use OpenTracing::GlobalTracer;

use HTTP::Headers;
use HTTP::Status;
use Time::HiRes qw( gettimeofday );

use constant CGI_REQUEST  => 'cgi_request';
use constant CGI_RUN      => 'cgi_run';
use constant CGI_SETUP    => 'cgi_setup';
use constant CGI_TEARDOWN => 'cgi_teardown';

our @implementation_import_params;

sub import {
    my $package = shift;
    @implementation_import_params = @_;
    
    my $caller  = caller;
    $caller->add_callback( init      => \&init      );
    $caller->add_callback( prerun    => \&prerun    );
    $caller->add_callback( postrun   => \&postrun   );
    $caller->add_callback( load_tmpl => \&load_tmpl );
    $caller->add_callback( teardown  => \&teardown  );
    
}



sub init {
    my $cgi_app = shift;
    
    _plugin_init_opentracing_implementation( $cgi_app );
    
    my %request_tags = _get_request_tags($cgi_app);
    my %query_params = _get_query_params($cgi_app);
    my $context      = _tracer_extract_context( $cgi_app );
    
    _plugin_start_active_span( $cgi_app, CGI_REQUEST, child_of => $context  );
    _plugin_add_tags(          $cgi_app, CGI_REQUEST, %request_tags         );
    _plugin_add_tags(          $cgi_app, CGI_REQUEST, %query_params         );
    _plugin_start_active_span( $cgi_app, CGI_SETUP                          );
    
}



sub prerun {
    my $cgi_app = shift;
    
    my %runmode_tags  = _get_runmode_tags($cgi_app);
    my %baggage_items = _get_baggage_items($cgi_app);
    
    _plugin_add_baggage_items( $cgi_app, CGI_SETUP,   %baggage_items        );
    _plugin_close_scope(       $cgi_app, CGI_SETUP                          );
    _plugin_add_baggage_items( $cgi_app, CGI_REQUEST, %baggage_items        );
    _plugin_add_tags(          $cgi_app, CGI_REQUEST, %runmode_tags         );
    _plugin_start_active_span( $cgi_app, CGI_RUN                            );
    
    return
}



sub postrun {
    my $cgi_app = shift;
    
    _plugin_close_scope(       $cgi_app, CGI_RUN                            );
    _plugin_start_active_span( $cgi_app, CGI_TEARDOWN                       );
    
    return
}



sub load_tmpl {
    my $cgi_app = shift;
    
    _plugin_close_scope(       $cgi_app, CGI_TEARDOWN                       );
    
    return
}



sub teardown {
    my $cgi_app = shift;
    
    my %http_status_tags = _get_http_status_tags($cgi_app);
    
    _plugin_close_scope(       $cgi_app, CGI_TEARDOWN                       );
    _plugin_add_tags(          $cgi_app, CGI_REQUEST, %http_status_tags     );
    _plugin_close_scope(       $cgi_app, CGI_REQUEST                        );
    
    return
}



sub _init_opentracing_implementation {
    my $cgi_app = shift;
    
    my @implementation_settings = @implementation_import_params;
    
    my @bootstrap_options = _get_bootstrap_options($cgi_app);
    $cgi_app->{__PLUGINS}{OPENTRACING}{BOOTSTRAP_OPTIONS} =
        [ @bootstrap_options ];
    
    push @implementation_settings, @bootstrap_options
        if @bootstrap_options;
    
    my $bootstrapped_tracer = OpenTracing::Implementation
        ->bootstrap_global_tracer( @implementation_settings );
    
    return $bootstrapped_tracer
}



sub _cgi_get_run_mode {
    my $cgi_app = shift;
    
    my $run_mode = $cgi_app->get_current_runmode();
    
    return $run_mode
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


sub _cgi_get_http_headers { # TODO: extract headers from CGI request
    my $cgi_app = shift;
    return HTTP::Headers->new();
}


sub _cgi_get_http_url {
    my $cgi_app = shift;
    
    my $query = $cgi_app->query();
    
    return $query->url(-path => 1);
}



sub get_opentracing_global_tracer {
    OpenTracing::GlobalTracer->get_global_tracer()
}


sub _get_request_tags {
    my $cgi_app = shift;
    
    my %tags = (
              'component'   => 'CGI::Application',
        maybe 'http.method' => _cgi_get_http_method($cgi_app),
        maybe 'http.url'    => _cgi_get_http_url($cgi_app),
    );
    

    return %tags
}

sub _get_query_params {
    my $cgi_app = shift;
    
    my %query_params = $cgi_app->query->Vars();
    
    my $processor = $cgi_app->can('opentracing_process_query_params')
        // \&_internal_default_query_param_processor;
    
    my %processed_params = ();
    
    while ( my ($param_name, $param_value) = each %query_params ) {
        my $processed_value = $cgi_app->$processor(
            $param_name, [ split /\0/, $param_value ]
        );
        next unless defined $processed_value;
        $processed_params{"http.query.$param_name"} = $processed_value
    }
    
    return %processed_params
}


sub _internal_default_query_param_processor {
    my ($self, $param, $vals) = @_;
    return join ',', @$vals;
}


sub _get_runmode_tags {
    my $cgi_app = shift;
    
    my %tags = (
        maybe 'run_mode'   => _cgi_get_run_mode($cgi_app),
        maybe 'run_method' => _cgi_get_run_method($cgi_app),
    );
    return %tags
}

sub _get_http_status_tags {
    my $cgi_app = shift;
    
    my %headers = $cgi_app->header_props();
    my $status = $headers{-status} or return (
        'http.status_code'    => '200',
    );
    my $status_code = [ $status =~ /^\s*(\d{3})/ ]->[0];
    my $status_mess = [ $status =~ /^\s*\d{3}\s*(.+)\s*$/ ]->[0];
    
    $status_mess = HTTP::Status::status_message($status_code)
        unless defined $status_mess;
    
    my %tags = (
        maybe 'http.status_code'    => $status_code,
        maybe 'http.status_message' => $status_mess,
    );
    return %tags
}


sub _get_bootstrap_options {
    my $cgi_app = shift;
    
    return unless $cgi_app->can('opentracing_bootstrap_options');
    
    my @bootstrap_options = $cgi_app->opentracing_bootstrap_options( );
    
    return @bootstrap_options
}



sub _get_baggage_items {
    my $cgi_app = shift;
    
    return unless $cgi_app->can('opentracing_baggage_items');
    
    my %baggage_items = $cgi_app->opentracing_baggage_items( );
    
    
    return %baggage_items
}



sub _tracer_extract_context {
    my $cgi_app = shift;
    
    my $http_headers = _cgi_get_http_headers($cgi_app);
    my $tracer = _plugin_get_tracer( $cgi_app );
    
    return $tracer->extract_context($http_headers)
}

sub _plugin_get_tracer {
    my $cgi_app = shift;
    return $cgi_app->{__PLUGINS}{OPENTRACING}{TRACER}
}

sub _plugin_init_opentracing_implementation {
    my $cgi_app = shift;
    
    my $tracer = _init_opentracing_implementation($cgi_app);
    $cgi_app->{__PLUGINS}{OPENTRACING}{TRACER} = $tracer;
}

sub _plugin_start_active_span {
    my $cgi_app        = shift;
    my $operation_name = shift;
    my %params         = @_;
    my $scope_name     = uc $operation_name;
    
    my $scope =
    _tracer_start_active_span( $cgi_app, $operation_name, %params );
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{$scope_name} = $scope;
}

sub _tracer_start_active_span {
    my $cgi_app        = shift;
    my $operation_name = shift;
    my %params         = @_;
    
    my $tracer = _plugin_get_tracer($cgi_app);
    $tracer->start_active_span( $operation_name, %params );
}

sub _plugin_add_tags {
    my $cgi_app        = shift;
    my $operation_name = shift;
    my %tags           = @_;
    my $scope_name     = uc $operation_name;
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{$scope_name}
        ->get_span->add_tags(%tags);
}

sub _plugin_add_baggage_items {
    my $cgi_app        = shift;
    my $operation_name = shift;
    my %baggage_items  = @_;
    my $scope_name     = uc $operation_name;
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{$scope_name}
        ->get_span->add_baggage_items( %baggage_items );
}

sub _plugin_close_scope {
    my $cgi_app        = shift;
    my $operation_name = shift;
    my $scope_name     = uc $operation_name;
    
    $cgi_app->{__PLUGINS}{OPENTRACING}{SCOPE}{$scope_name}->close
}



1;
