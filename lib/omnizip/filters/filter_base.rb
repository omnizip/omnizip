# frozen_string_literal: true

# FilterBase is a historical alias for Omnizip::Filter. New code should
# inherit from Omnizip::Filter directly; FilterBase is kept for
# backward compatibility with existing subclasses (BcjX86, BcjArm, …).
Omnizip::Filters::FilterBase = Omnizip::Filter
