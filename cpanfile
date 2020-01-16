requires        'CGI::Application';
requires        'CGI::Application::Server';
requires        'OpenTracing::GlobalTracer';
requires        'OpenTracing::Implementation';
requires        'Time::HiRes';

on 'test' => sub {
    requires            "Test::Most";
};
