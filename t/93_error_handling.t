use Test::Most ;
use Test::MockObject;
use Test::OpenTracing::Integration;
use Test::WWW::Mechanize::CGIApp;

{
    package MyTest::WithErrorBase;
    use base 'CGI::Application';

    use CGI::Application::Plugin::OpenTracing qw/Test/;
    use OpenTracing::GlobalTracer qw/$TRACER/;

    sub run_modes {
        run_mode_die => 'method_die',
        run_mode_one => 'method_one',
    }

    sub method_die { die 'Something wrong within "Method Die"' }

    sub method_one {
        my $scope = $TRACER->start_active_span('level_one');
        inside_die();
    }

    sub inside_die { die 'Something wrong within "Inside Die"' }
}

my $mech = Test::WWW::Mechanize::CGIApp->new(app => 'MyTest::WithErrorBase');

eval { $mech->get('https://test.tst/test.cgi?rm=run_mode_die') };
global_tracer_cmp_easy(
    [
        {
            operation_name          => 'cgi_application_request',
            level                   => 0,
            tags                    => {
                'component'             => 'CGI::Application',
                'http.method'           => 'GET',
                'http.url'              => 'https://test.tst/test.cgi',
                'http.query.rm'         => 'run_mode_die',
                'http.status_code'      => 500,
                'run_mode'              => 'run_mode_die',
                'run_method'            => 'method_die',
                'error'                 => 1,
                'message'               => re(qr/Method Die/),
            },
        },
        {
            operation_name          => 'cgi_application_run',
            level                   => 1,
            tags                    => {
                'error'                 => 1,
                'message'               => re(qr/Method Die/),
            },
        },
    ], 'CGI::App [WithErrorBase/run_mode_die], dies "Method Die" at [method_die]'
);

eval { $mech->get('https://test.tst/test.cgi?rm=run_mode_one') };
global_tracer_cmp_easy(
    [
        {
            operation_name          => 'cgi_application_request',
            level                   => 0,
            tags                    => {
                'component'             => 'CGI::Application',
                'http.method'           => 'GET',
                'http.url'              => 'https://test.tst/test.cgi',
                'http.query.rm'         => 'run_mode_one',
                'http.status_code'      => 500,
                'run_mode'              => 'run_mode_one',
                'run_method'            => 'method_one',
                'error'                 => 1,
                'message'               => re(qr/Inside Die/),
            },      
        },
        {
            operation_name          => 'cgi_application_run',
            level                   => 1,
            tags                    => {
                'error'                 => 1,
                'message'               => re(qr/Inside Die/),
            },
        },
        {
            operation_name          => 'level_one',
            level                   => 2,
            tags                    => {
                'error'                 => 1,
                'message'               => re(qr/Inside Die/),
            },
        },
    ], 'CGI::App [WithErrorBase/run_mode_one], dies "Inside Die" at [level_one/inside_die]'
);

eval { $mech->get('https://test.tst/test.cgi?rm=run_mode_xxx') };
global_tracer_cmp_easy(
    [
        {
            operation_name          => 'cgi_application_request',
            level                   => 0,
            tags                    => {
                'component'             => 'CGI::Application',
                'http.method'           => 'GET',
                'http.url'              => 'https://test.tst/test.cgi',
                'http.query.rm'         => 'run_mode_xxx',
                'http.status_code'      => 500,
                'error'                 => 1,
                'run_mode'              => 'run_mode_xxx',
                'message'               => re(qr/No such run mode/),
            },
        },
        {
            operation_name          => 'cgi_application_run',
            level                   => 1,
            tags                    => {
                'error'                 => 1,
                'message'               => re(qr/No such run mode/),
            },
        },
    ], 'CGI::App [WithErrorBase/run_mode_xxx] invalid'
);

{
    package MyTest::WithErrorMode;
    use base 'MyTest::WithErrorBase';

    sub cgiapp_init { $_[0]->error_mode('show_error') }

    sub show_error {
        my $self = shift;

        $self->header_add(-status => '402');

        return 'Pay up'
    }
}

$mech = Test::WWW::Mechanize::CGIApp->new(app => 'MyTest::WithErrorMode');

$mech->get('https://test.tst/test.cgi?rm=run_mode_die');
global_tracer_cmp_easy(
    [
        {
            operation_name          => 'cgi_application_request',
            level                   => 0,
            tags                    => {
                'component'             => 'CGI::Application',
                'http.method'           => 'GET',
                'http.url'              => 'https://test.tst/test.cgi',
                'http.query.rm'         => 'run_mode_die',
                'http.status_code'      => '402',
                'http.status_message'   => "Payment Required",
                'run_mode'              => 'run_mode_die',
                'run_method'            => 'method_die',
            },
        },
        {
            operation_name          => 'cgi_application_run',
            level                   => 1,
            tags                    => {},
        },
    ], 'CGI::App [WithErrorMode/run_mode_die], dies "Method Die" at [method_die]'
);

$mech->get('https://test.tst/test.cgi?rm=run_mode_one');
global_tracer_cmp_easy(
    [
        {
            operation_name          => 'cgi_application_request',
            level                   => 0,
            tags                    => {
                'component'             => 'CGI::Application',
                'http.method'           => 'GET',
                'http.url'              => 'https://test.tst/test.cgi',
                'http.query.rm'         => 'run_mode_one',
                'http.status_code'      => '402',
                'http.status_message'   => "Payment Required",
                'run_mode'              => 'run_mode_one',
                'run_method'            => 'method_one',
            },
        },
        {
            operation_name          => 'cgi_application_run',
            level                   => 1,
            tags                    => {},
        },
        {
            operation_name          => 'level_one',
            level                   => 2,
            tags                    => {
                'error'                 => 1,
                'message'               => re(qr/Inside Die/),
            },
        },
    ], 'CGI::App [WithErrorMode/run_mode_one], dies "Inside Die" at [level_one/inside_die]'
);

done_testing();
