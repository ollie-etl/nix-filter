# This is a pure and self-contained library
rec {
  # Default to filter when calling this lib.
  __functor = self: filter;

  # A proper source filter
  filter =
    {
      # Base path to include
      root
    , # Derivation name
      name ? "source"
    , # Only include the following path matches.
      #
      # Allows all files by default.
      include ? [ (_:_:_: true) ]
    , # Ignore the following matches
      exclude ? [ ]
    }:
      assert _pathIsDirectory root;
      let
        callMatcher = args: _toMatcher ({ inherit root; } // args);
        include_ = map (callMatcher { matchParents = true; }) include;
        exclude_ = map (callMatcher { matchParents = false; }) exclude;
      in
      builtins.path {
        inherit name;
        path = root;
        filter = path: type:
          (builtins.any (f: f path type) include_) &&
          (!builtins.any (f: f path type) exclude_);
      };

  # Match a directory and any path inside of it
  inDirectory =
    directory:
    args:
    path_filter:
    let
      # Convert `directory` to a path to clean user input.
      directory_ = _toCleanPath args.root directory;
    in
    path: type:
    directory_ == path
    # Add / to the end to make sure we match a full directory prefix
    || (
      (_hasPrefix (directory_ + "/") path)
      && (path_filter (builtins.baseNameOf path))
      );

  # Match any directory
  isDirectory = _: _: type: type == "directory";

  # Combines matchers
  and = a: b: args:
    let
      toMatcher = _toMatcher args;
    in
    path: type:
      (toMatcher a path type) && (toMatcher b path type);

  # Combines matchers
  or_ = a: b: args:
    let
      toMatcher = _toMatcher args;
    in
    path: type:
      (toMatcher a path type) || (toMatcher b path type);

  # Or is actually a keyword, but can also be used as a key in an attrset.
  or = or_;

  # Match paths with the given extension
  matchExt = ext:
    args: path: type:
      _hasSuffix ".${ext}" path;

  # Filter out files or folders with this exact name
  matchName = name:
    root: path: type:
      builtins.baseNameOf path == name;

  # Wrap a matcher with this to debug its results
  debugMatch = label: fn:
    args: path: type:
      let
        ret = fn args path type;
        retStr = if ret then "true" else "false";
      in
      builtins.trace "label=${label} path=${path} type=${type} ret=${retStr}"
        ret;

  # Add this at the end of the include or exclude, to trace all the unmatched paths
  traceUnmatched = args: path: type:
    builtins.trace "unmatched path=${path} type=${type}" false;

  # Lib stuff

  # If an argument to include or exclude is a path, transform it to a matcher.
  _toMatcher = args: f:
    let
      path_ = _toCleanPath args.root f;
      basename = baseNameOf (toString path_);
      parent = builtins.dirOf path_;
      pathIsDirectory = _pathIsDirectory path_;
    in
    if builtins.isFunction f then f args
    else path: type:
      (if pathIsDirectory then
        inDirectory path_ args (_: true) path type
      else
        inDirectory parent args (f: f == basename) path type
      ) || args.matchParents
      && type == "directory"
      && _hasPrefix "${path}/" path_;


  # Makes sure a path is:
  # * absolute
  # * doesn't contain superfluous slashes or ..
  #
  # Returns a string so there is no risk of adding it to the store by mistake.
  _toCleanPath = absPath: path:
    assert _pathIsDirectory absPath;
    if builtins.isPath path then
      toString path
    else if builtins.isString path then
      if builtins.substring 0 1 path == "/" then
        path
      else
        toString (absPath + ("/" + path))
    else
      throw "unsupported type ${builtins.typeOf path}, expected string or path";

  _hasSuffix =
    # Suffix to check for
    suffix:
    # Input string
    content:
    let
      lenContent = builtins.stringLength content;
      lenSuffix = builtins.stringLength suffix;
    in
    lenContent >= lenSuffix
    && builtins.substring (lenContent - lenSuffix) lenContent content == suffix;

  _hasPrefix =
    # Prefix to check for
    prefix:
    # Input string
    content:
    let
      lenPrefix = builtins.stringLength prefix;
    in
    prefix == builtins.substring 0 lenPrefix content;

  # Returns true if the path exists and is a directory and false otherwise
  _pathIsDirectory = p:
    let
      parent = builtins.dirOf p;
      base = builtins.unsafeDiscardStringContext (builtins.baseNameOf p);
      inNixStore = builtins.storeDir == toString parent;
    in
    # If the parent folder is /nix/store, we assume p is a directory. Because
      # reading /nix/store is very slow, and not allowed in every environments.
    inNixStore ||
    (
      builtins.pathExists p &&
      (builtins.readDir parent).${builtins.unsafeDiscardStringContext base} == "directory"
    );

}
