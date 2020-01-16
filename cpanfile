requires        'CGI::Application';
requires        'CGI::Application::Server';
requires        'OpenTracing::GlobalTracer';
requires        'OpenTracing::Implementation';
requires        'Time::HiRes';

on 'develop' => sub {
    requires    "ExtUtils::MakeMaker::CPANfile";
};

on 'test' => sub {
    requires            "Test::Most";
};
