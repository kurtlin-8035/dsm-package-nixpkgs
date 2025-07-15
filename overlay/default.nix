final: prev: {
  buildSynologyBinaryPackage = {
    DSM7-2 = final.lib.makeOverridable (
      {
        pname,
        version,
        drvs,
        description ? "",
        displayName ? pname,
        maintainer ? "A maintainer",
        maintainerUrl ? "",
        distributorUrl ? "",
        debug ? false,
      }:
      final.callPackage (
        {
          lib,
          runCommandNoCC,
          writeClosure,
          writeScript,
          symlinkJoin,
          makeWrapper,
          pkgsStatic,
        }:
        let
          name = "${pname}-${version}";

          escapeSed = lib.escape [ "/" ];

          fake_fhs = symlinkJoin {
            name = "${name}-fhs";
            paths = drvs;
          };

          bwrap-run = writeScript "bwrap-run" ''
            #!/usr/bin/env bash

            LOCAL_ROOT="$(dirname $(dirname $0))"
            $LOCAL_ROOT/bin/bwrap --bind / / --bind "$LOCAL_ROOT/nix" /nix "$@"
          '';

          # Not sure why but prev.propagatedBuildInputs is not empty and makes
          # us capture unused closure.
          static-bubblewrap = pkgsStatic.bubblewrap.overrideDerivation (prev: {
            buildInputs = prev.buildInputs ++ prev.propagatedBuildInputs;
            propagatedBuildInputs = [ ];
          });

          privilegeSetting = {
            defaults.run-as = "package";
          };
        in
        runCommandNoCC name
          {
            nativeBuildInputs = [ makeWrapper ];
          }
          ''
            function mkBWrapper() {
                local bin_path="$1"
                local bin="$(basename $bin)"
                local bin_wrapped=".''${bin}-wrapped"

                pushd "$(dirname $bin_path)"

                mv "$bin" ".$bin-wrapped"

                cat << EOL > "$bin"
            #!/usr/bin/env bash

            LOCAL_ROOT="\$(dirname \$(dirname \$(realpath \$0)))"
            if [ -e /nix/IS_SANDBOXED ]; then
              "$bin_wrapped" "\$@"
            else
              "\$LOCAL_ROOT/bin/bwrap" --bind / / --bind "\$LOCAL_ROOT/nix" /nix --setenv "PATH" "\$LOCAL_ROOT/bin:\$PATH" "$bin_wrapped" "\$@"
            fi
            EOL

                chmod 555 "$bin"

                popd
            }

            mkdir $out

            mkdir tmp
            pushd tmp

            sed \
                -e 's/@@PACKAGE@@/${escapeSed pname}/' \
                -e 's/@@VERSION@@/${escapeSed version}/' \
                -e 's/@@DISPLAY_NAME@@/${escapeSed displayName}/' \
                -e 's/@@DESCRIPTION@@/${escapeSed description}/' \
                -e 's/@@MAINTAINER@@/${escapeSed maintainer}/' \
                -e 's/@@MAINTAINER_URL@@/${escapeSed maintainerUrl}/' \
                -e 's/@@DISTRIBUTOR_URL@@/${escapeSed distributorUrl}/' \
                ${./INFO} > INFO
            cp -v ${./PACKAGE_ICON.PNG} PACKAGE_ICON.PNG
            cp -v ${./PACKAGE_ICON_256.PNG} PACKAGE_ICON_256.PNG

            mkdir conf

            bin_paths="["
            for bin in ${fake_fhs}/bin/*; do
                bin_paths="''${bin_paths}\"usr/local/bin/$(basename $bin)\","
            done
            bin_paths=$(sed 's/.$//' <<< "$bin_paths")
            bin_paths="''${bin_paths}]"

            echo $bin_paths

            cat <<EOL > conf/resource
            {
              "usr-local-linker": {
                "bin": $bin_paths
              }
            }
            EOL

            echo '${builtins.toJSON privilegeSetting}' > conf/privilege

            mkdir scripts
            cp -v ${./start-stop-status} scripts/start-stop-status
            cp -v ${./start-stop-status} scripts/postinst

            cp -v ${./start-stop-status} scripts/postuninst
            cp -v ${./start-stop-status} scripts/preinst
            cp -v ${./start-stop-status} scripts/preuninst
            cp -v ${./start-stop-status} scripts/preupgrade
            cp -v ${./start-stop-status} scripts/postupgrade
            chmod 755 scripts/*

            popd # tmp

            mkdir package

            mkdir -p package/nix
            touch package/nix/IS_SANDBOXED

            mkdir -p package/nix/store
            input="${writeClosure drvs}"
            while IFS= read -r line
            do
                cp -r "$line" package/nix/store
            done < "$input"

            cp -vr ${fake_fhs}/* package/
            chmod u+w package/bin/

            mkdir -p package/usr/local
            ln -s ../../bin package/usr/local/bin

            echo "wrap all program to bwrap"
            pushd package/bin
            for bin in ./*; do
                mkBWrapper "$bin"
            done
            popd

            cp ${bwrap-run} package/bin/bwrap-run
            cp ${static-bubblewrap}/bin/bwrap package/bin/bwrap

            tar --owner=root --group=root --xform s:'^./':: -caf tmp/package.tgz -C package .
            tar --owner=root --group=root --xform s:'^./':: -cf "$out/${name}.spk" -C tmp .

            if ${if debug then "true" else "false"}; then
              cp -r tmp $out/for_debug
              cp -r package $out/for_debug
              rm $out/for_debug/package.tgz
            fi
          ''
      ) { }
    );
  };
  SynologyPackageALaCarte = final.lib.mergeAttrsList (
    final.lib.forEach [ "DSM7-2" ] (name: {
      ${name} = builtins.mapAttrs (
        k: v:
        if final.lib.isDerivation (final."${k}") then
          let
            drv = final."${k}";
          in
          final.buildSynologyBinaryPackage.${name} {
            inherit (drv) pname version;
            drvs = [ drv ];
            description = final.lib.attrByPath [
              "meta"
              "description"
            ] null drv;
            maintainer = final.lib.attrByPath [
              "meta"
              "homepage"
            ] null drv;
            maintainerUrl = final.lib.attrByPath [
              "meta"
              "homepage"
            ] null drv;
          }
        else
          v
      ) final;
    })
  );
}
