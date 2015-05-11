module Extensions::ActiveRecord::ConnectionAdapters::TableDefinition
  def self.included(module_)
    module_.alias_method_chain :userstamps, :compatibility
    module_.alias_method_chain :actable, :schema_plus
  end

  # Enforces a valid date range for the given table.
  #
  # @see ActiveRecord::Base#currently_valid? for more details.
  def time_bounded(*args)
    datetime :valid_from, *args
    datetime :valid_to, *args
  end

  def userstamps_with_compatibility(*args)
    userstamps_without_compatibility(false, *args)
  end

  def actable_with_schema_plus(*args, **kwargs)
    kwargs[:index] ||= :unique
    actable_without_schema_plus(*args, **kwargs)
  end
end
