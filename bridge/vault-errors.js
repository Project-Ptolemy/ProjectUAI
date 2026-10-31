'use strict';

// Filesystem exceptions contain absolute paths. Keep those out of model results
// and HTTP responses; only intentional validation messages are public.
function publicError(error) {
  if (Number.isInteger(error?.status) && error.status >= 400 && error.status < 600) {
    return { status: error.status, error: String(error.message).slice(0, 500) };
  }
  const known = {
    ENOENT: [404, 'The vault folder or note is unavailable. Refresh the connection and check its path.'],
    EACCES: [403, 'The bridge cannot access this vault file. Check its filesystem permissions.'],
    EPERM: [403, 'The bridge cannot access this vault file. Check its filesystem permissions.'],
    ENOSPC: [507, 'The bridge computer has no space left for this save.'],
    EBUSY: [409, 'This vault file is busy. Check its current contents before retrying.'],
    EEXIST: [409, 'This vault path already exists. Refresh before retrying.'],
    ENOTDIR: [400, 'A vault path component is not a folder.'],
  };
  const [status, message] = known[error?.code] || [500, 'The vault operation could not finish. Inspect the note before repeating an edit.'];
  return { status, error: message };
}

module.exports = { publicError };
