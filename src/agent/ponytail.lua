-- Adapted from Ponytail by DietrichGebert, revision
-- 96608e078b2d5ea607c5c3b8b5a54d1c1fba6846 (November 15, 2026).
-- https://github.com/DietrichGebert/ponytail
-- MIT License
-- Copyright (c) 2026 DietrichGebert
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
return function(env)
	return [[Ponytail workflow (UAI):
- Choose the smallest change that fully solves the task. Inspect
  affected callers, tests, fixtures, config and exports; fix the shared cause.
- Reuse the project's helper/component/service, then platform features, then an
  installed dependency. Avoid dependencies, wrappers and options for a few lines.
  Keep existing layers and readable code; prefer deletion.
- Preserve security, validation, error handling, data, accessibility, cleanup and real-host
  calibration. Check new nontrivial behavior; disclose shortcuts' limits and replacements.
- Review inputs, build, inspect outputs, then verify. Briefly report results,
  evidence and unchecked limits. Never trade completeness for a short diff.]]
end
