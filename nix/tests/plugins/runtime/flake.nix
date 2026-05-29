{
  outputs =
    { self }:
    {
      openclawPlugin = {
        name = "runtime";
        skills = [ ];
        packages = [ ];
        needs = { };
        plugins = [
          {
            id = "runtime-test";
            path = "${self.outPath}/plugin";
          }
        ];
      };
    };
}
