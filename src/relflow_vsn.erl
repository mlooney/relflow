%% rewrite app and app.src files to update vsn field
-module(relflow_vsn).
-include("relflow.hrl").
-compile(export_all).

-define(AppHeader, "%% Vsn auto-managed by relflow utility.\n%% DO NOT CHANGE VSN FIELD MANUALLY!").
-define(is_level(Level), (Level == major orelse Level == minor orelse Level == patch)).

int(Str) ->
    {I,""} = string:to_integer(Str), I.

str2vsn(Str) ->
    case string:tokens(Str, ".") of
        [Maj,Min,Pat] ->
            {int(Maj), int(Min), int(Pat)};
        [Maj,Min] ->
            {int(Maj), int(Min), 0};
        [Maj] ->
            int(Maj)
    end.

vsn2str(I) when is_integer(I) ->
    lists:flatten(io_lib:format("~B",[I]));
vsn2str({Maj,Min,Pat}) ->
    lists:flatten(io_lib:format("~B.~B.~B",[Maj,Min,Pat])).

bump_vsn(I, _) when is_integer(I) -> I+1;
bump_vsn({Maj,Min,Pat}, major) -> {Maj+1, Min, Pat};
bump_vsn({Maj,Min,Pat}, minor) -> {Maj, Min+1, Pat};
bump_vsn({Maj,Min,Pat}, patch) -> {Maj, Min, Pat+1}.

%%  bump_version("1.0.0", patch) --> "1.0.1"
%%  bump_version("1.0.0", minor) --> "1.1.0"
%%  bump_version("1.0.0", major) --> "2.0.0"
bump_version(Str, Level) when is_list(Str) andalso ?is_level(Level) ->
    vsn2str(bump_vsn(str2vsn(Str), Level)).

rewrite_appfile_inplace(Filepath, NewVsn) when is_list(Filepath) ->
    ?DEBUG("rewriting inplace ~s",[Filepath]),
    {ok, [{application, AppName, Sections}]} = file:consult(Filepath),
    Vsn = proplists:get_value(vsn, Sections),
    NewSections = [{vsn, NewVsn} | proplists:delete(vsn, Sections)],
    Contents = io_lib:format("~s\n~p.~n",[?AppHeader, {application, AppName, NewSections}]),
    ok = file:write_file(Filepath, Contents),
    ?DEBUG("Modified version in appfile ~s --> ~s in: ~s",[Vsn, NewVsn, Filepath]),
    {ok, AppName, Vsn, NewVsn}.

%% given path to .app/.app.src, bumps vsn in .app.src, applies new vsn to .app
%% this avoids having to run make just to rewrite the .app file.
bump_dot_apps(AppFile, AppSrcFile, NewVsn) when is_list(NewVsn) ->
    case rewrite_appfile_inplace(AppSrcFile, NewVsn) of
        {ok, AppName, OldVsn, NewVsn} =TT->
            {ok, AppName, OldVsn, NewVsn} = rewrite_appfile_inplace(AppFile, NewVsn),
            ?INFO("Modified appfiles for ~s @ ~s --> ~s",[AppName, OldVsn, NewVsn]),
            {ok, OldVsn, NewVsn}
    end.

read_appfile_vsn(Path) ->
    {ok, [{application, _AppName, Sections}]} = file:consult(Path),
    Vsn = proplists:get_value(vsn, Sections),
    Vsn.


%% actually takes the current {release, ...} section from relx.config,
%% copies it, bumps the version, and appends to the relx.config without
%% rewriting the entire file. This preserves comments and whitespace.
bump_relx_vsn(File, RelName, PrevVsn) when is_atom(RelName), is_list(PrevVsn) ->
    {ok, Terms} = file:consult(File),
    PrevRelease = case lists:filter(
            fun
                (T) when is_tuple(T) ->
                    element(1, T) == release andalso
                    element(2, T) == {RelName, PrevVsn};
                (_) ->
                    false
            end, Terms) of
        [PR] ->
            PR;
        [] ->
            throw(no_previous_release_term_in_relx_config)
    end,
    NewVsn = bump_version(PrevVsn, minor),
    NewReleaseTuple = setelement(2, PrevRelease, {RelName, NewVsn}),
    ?INFO("Modified relx.config, added new release @ ver ~s",[NewVsn]),
    ok = file:write_file(File, io_lib:format("\n\n~p.",[NewReleaseTuple]), [append]),
    {ok, NewVsn}.
    
