requires        'OpenTracing::Constants::CarrierFormat';
requires        'OpenTracing::GlobalTracer';
requires        'OpenTracing::Implementation';
requires        'HTTP::Request';
requires        'Time::HiRes';

on 'develop' => sub {
    requires    "ExtUtils::MakeMaker::CPANfile";
};

on 'test' => sub {
    requires    "Test::Most";
    requires    "Test::OpenTracing::Integration";
    requires    "Test::MockObject";
}

# on 'examples' => sub {
#     requires    'CGI::Application';
#     requires    'CGI::Application::Server';
# };