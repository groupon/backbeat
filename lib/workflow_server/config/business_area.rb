module WorkflowServer

  def self.Bill?
    Class.new do
      def self.Hey
        user = (ENV['USER'] || ENV['USERNAME']).capitalize
        ["Hello #{user}, what's happening? Listen, are you gonna have those TPS reports for us this afternoon?",
         "Well then I suppose we should go ahead and have a little talk...",
         "Oh, oh, yea...I forgot. I'm gonna also need you to come in Sunday too. We, uh, lost some people this week and we need to sorta catch up. Thanks.",
         "Oh, and next Friday is Hawaiian shirt day. So, you know, if you want to you can go ahead and wear a Hawaiian shirt and jeans.",
         "#{user}, we're gonna need to go ahead and move you downstairs into storage B. We have some new people coming in, and we need all the space we can get. So if you could go ahead and pack up your stuff and move it down there, that would be terrific, mmmKay? ",
         "Grrrreat.",
         "Can you move a little to the left? Oooooh. Yeah, that's it, greeeeeeat.",
         "Yeah...",
         "Uh, you're going to have to talk to payroll about that.",
         "Eech. Ooh. Yeah. Um... I'm going to have to go ahead and sort of disagree with you there.",
         "Hello, #{user}. What's happening? Ahh...We have sort of a problem here. Yeah. You apparently didn't put one of the new cover sheets on your T.P.S. Reports.",
        "Ahh...We have sort of a problem here.",
        "Mmm...Yeah. You see, we're putting the cover sheets on all T.P.S. Reports now before they go out. Did you see the memo about this?",
        "I'll go ahead and make sure you get another copy of that memo Mmmm, Ok?"].sample
      end
    end
  end

end
