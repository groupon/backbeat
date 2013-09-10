TorqueBox.configure do
  queue '/queues/accounting_backbeat_internal' do
    processor WorkflowServer::Async::MessageProcessor
  end
end