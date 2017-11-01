require 'highline'

# Some patch for HighLine, to provide exact same interface after using
# readline=true for its `choose' method, required by our `ask_with_menu'
class HighLine
  def readline_ask_for_choose( question, answer_type = String, &details ) # :yields: question
    @question ||= Question.new(question, answer_type, &details)
    @question.readline = true
    return gather if @question.gather

    # changes here, show question here but not when reask question after invalid
    # question
    say(@question)
    begin
      # delete the question string, because after user give an invalid answer,
      # we don't want to redisplay the question again, but just show `? ' for
      # user to answer again.
      @question = Question.new("", answer_type, &details)
      @question.readline = true
      @answer = @question.answer_or_default(get_response)
      unless @question.valid_answer?(@answer)
        explain_error(:not_valid)
        raise QuestionError
      end
      @answer = @question.convert(@answer)

      if @question.in_range?(@answer)
        if @question.confirm
          # need to add a layer of scope to ask a question inside a
          # question, without destroying instance data
          context_change = self.class.new(@input, @output, @wrap_at, @page_at, @indent_size, @indent_level)
          if @question.confirm == true
            confirm_question = "Are you sure?  "
          else
            # evaluate ERb under initial scope, so it will have
            # access to @question and @answer
            template  = ERB.new(@question.confirm, nil, "%")
            confirm_question = template.result(binding)
          end
          unless context_change.agree(confirm_question)
            explain_error(nil)
            raise QuestionError
          end
        end

        @answer
      else
        explain_error(:not_in_range)
        raise QuestionError
      end
    rescue QuestionError
      retry
    rescue ArgumentError, NameError => error
      raise if error.is_a?(NoMethodError)
      if error.message =~ /ambiguous/
        # the assumption here is that OptionParser::Completion#complete
        # (used for ambiguity resolution) throws exceptions containing
        # the word 'ambiguous' whenever resolution fails
        explain_error(:ambiguous_completion)
      else
        explain_error(:invalid_type)
      end
      retry
    rescue Question::NoAutoCompleteMatch
      explain_error(:no_completion)
      retry
    ensure
      @question = nil    # Reset Question object.
    end
  end

  def readline_choose( *items, &details )
    @menu = @question = Menu.new(&details)
    @menu.choices(*items) unless items.empty?

    # Set auto-completion
    @menu.completion = @menu.options
    # Set _answer_type_ so we can double as the Question for ask().
    @menu.answer_type = if @menu.shell
      lambda do |command|    # shell-style selection
        first_word = command.to_s.split.first || ""

        options = @menu.options
        options.extend(OptionParser::Completion)
        answer = options.complete(first_word)

        if answer.nil?
          raise Question::NoAutoCompleteMatch
        end

        [answer.last, command.sub(/^\s*#{first_word}\s*/, "")]
      end
    else
      @menu.options          # normal menu selection, by index or name
    end

    # Provide hooks for ERb layouts.
    @header   = @menu.header
    @prompt   = @menu.prompt
    if @menu.shell
      # changes here, use modified version of ask
      selected = readline_ask_for_choose("Ignored", @menu.answer_type)
      @menu.select(self, *selected)
    else
      # changes here, use modified version of ask
      selected = readline_ask_for_choose("Ignored", @menu.answer_type)
      @menu.select(self, selected)
    end
  end
end

module Kernel
  extend Forwardable
  def_delegators :$terminal, :readline_ask_for_choose, :readline_choose
end
