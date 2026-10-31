using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.Loader;
using System.Text.Json;
using OpenClaw.Shared;
using OpenClaw.Connection;
using OpenClawTray.Services;

internal static class Program
{
    static readonly JsonSerializerOptions Json = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    static readonly string Work = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../"));
    static readonly string Product = Path.GetFullPath(Path.Combine(Work, "../gateway-voice-successor-20261031/src/OpenClaw.Tray.WinUI/bin/Debug/net10.0-windows10.0.22621.0/win-x64"));
    static readonly string Output = Path.GetFullPath(Path.Combine(Work, "../PR1915-successor-evidence-2026-10-31/native/B"));
    static readonly object EventLock = new();
    static string PrivateRoot = "", Url = "";
    static Input Config = new();
    static string AllowedPath = "", ReadPath = "", ControlPath = "", Profile = "", GatewayId = "";

    public static async Task<int> Main(string[] args)
    {
        AssemblyLoadContext.Default.Resolving += (_, name) => {
            var path = Path.Combine(Product, name.Name + ".dll");
            return File.Exists(path) ? AssemblyLoadContext.Default.LoadFromAssemblyPath(path) : null;
        };
        return await Run(args);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static async Task<int> Run(string[] args)
    {
        Directory.CreateDirectory(Output);
        try {
            using var locator = JsonDocument.Parse(File.ReadAllText(Path.Combine(Work, "private-location.json")));
            PrivateRoot = locator.RootElement.GetProperty("PrivateRoot").GetString()!;
            if (!System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(PrivateRoot), "^OpenClaw-PR1915-Successor-[a-f0-9]{32}$") || !Path.GetFullPath(PrivateRoot).Contains("\\AppData\\Local\\Temp\\", StringComparison.OrdinalIgnoreCase)) throw new SafeFailure("private_root_not_task_temporary");
            Config = JsonSerializer.Deserialize<Input>(File.ReadAllText(Path.Combine(PrivateRoot, "fixture-private.json")), Json)!;
            if (Config.GatewayPort != 19515 || Config.BackendPort != 19817) throw new InvalidOperationException("Unexpected fixture ports.");
            Url = $"ws://127.0.0.1:{Config.GatewayPort}";
            Profile = Path.Combine(PrivateRoot, "app-profile");
            Environment.SetEnvironmentVariable("OPENCLAW_TRAY_DATA_DIR",Profile);
            Environment.SetEnvironmentVariable("APPDATA",Path.Combine(PrivateRoot,"appdata"));
            Environment.SetEnvironmentVariable("LOCALAPPDATA",Path.Combine(PrivateRoot,"localappdata"));
            var metadataPath = Path.Combine(PrivateRoot, "app-profile-private.json");
            if (File.Exists(metadataPath)) GatewayId = JsonDocument.Parse(File.ReadAllText(metadataPath)).RootElement.GetProperty("gatewayRecordId").GetString()!;
            else { GatewayId = Guid.NewGuid().ToString(); File.WriteAllText(metadataPath, JsonSerializer.Serialize(new { profilePath = Profile, gatewayRecordId = GatewayId }, Json)); }
            AllowedPath = new GatewayRegistry(Profile).GetIdentityDirectory(GatewayId);
            ReadPath = Path.Combine(PrivateRoot, "readonly-device-v2");
            ControlPath = Path.Combine(PrivateRoot, "provisioning-control-device");
            Record("helper_start", new { command = args.FirstOrDefault(), assemblyMode = "verified existing DLLs; no product rebuild" });
            switch (args.FirstOrDefault()) {
                case "provision": await Provision(); break;
                case "check-readonly": await CheckReadonly(); break;
                case "create-profile": CreateProfile(); break;
                case "set-profile-relay": SetProfileRelay(); break;
                default: throw new InvalidOperationException("Use provision, check-readonly, or create-profile.");
            }
            Record("helper_complete", new { command = args[0] });
            return 0;
        } catch (Exception ex) {
            // Never emit exception bodies, provider errors, credentials, device keys, or private JSON.
            Record("helper_failed", new { exceptionType = ex.GetType().Name, classification = ex is SafeFailure safe ? safe.Classification : "finite_helper_failure" });
            return 1;
        }
    }

    static void Record(string name, object details) {
        var entry = new { at = DateTimeOffset.UtcNow, name, details };
        lock(EventLock) { File.AppendAllText(Path.Combine(Output, "auth-client-events.jsonl"), JsonSerializer.Serialize(entry) + Environment.NewLine);
        Console.WriteLine(JsonSerializer.Serialize(entry)); }
    }
    sealed class SafeFailure(string classification) : Exception { public string Classification { get; } = classification; }
    sealed class Input { public int GatewayPort {get;set;} public int BackendPort {get;set;} public string GatewayToken {get;set;}=""; public string ControlToken {get;set;}=""; }
    sealed class MethodLogger : IOpenClawLogger {
        public void Info(string message) { const string prefix="[GatewayClient] Sending frame: "; if(message.StartsWith(prefix)) Record("production_rpc_intent", new { method=message[prefix.Length..] }); }
        public void Debug(string message) {} public void Warn(string message) {} public void Error(string message,Exception? ex=null) {}
    }

    static OpenClawGatewayClient Client(string path, bool shared, bool interactive=false) {
        // Base client requires a nonempty token. With shared=false its only supplied token
        // is this identity's genuine stored device token; no shared/admin fallback exists.
        var token=shared ? Config.GatewayToken : DeviceIdentity.TryReadStoredDeviceToken(path) ?? throw new SafeFailure("missing_stored_device_credential");
        return new(Url,token,new MethodLogger(),identityPath:path,requireExistingIdentity:!shared) {ClientIdentity=interactive ? OperatorClientIdentity.Interactive : OperatorClientIdentity.Cli};
    }
    static async Task<bool> Ready(OpenClawGatewayClient client) {
        client.StatusChanged += (_, status) => Record("connection_status", new { status=status.ToString() }); client.ConnectionFailure += (_, kind) => Record("connection_failure", new { kind=kind.ToString() }); await client.ConnectAsync();
        var until=Stopwatch.StartNew();
        while(until.Elapsed < TimeSpan.FromSeconds(15)) {
            if(client.HasHandshakeSnapshot && client.IsConnectedToGateway) return true;
            if(client.IsPairingRequired || client.IsAuthFailed) return false;
            await Task.Delay(100);
        }
        return false;
    }
    static void Hello(string label, OpenClawGatewayClient client) => Record("actual_hello_grants",new { label, scopes=client.GrantedOperatorScopes.ToArray(), ttsStatusAdvertised=client.AdvertisedServerMethods.Contains("tts.status"), ttsSpeakAdvertised=client.AdvertisedServerMethods.Contains("tts.speak") });
    static async Task<OpenClawGatewayClient> Paired(string path,string label,OpenClawGatewayClient? approver=null,bool interactive=false) {
        var client=Client(path,true,interactive);
        if(await Ready(client)) { Hello(label,client); return client; }
        if(client.IsPairingRequired && client.PairingRequiredRequestId is { } request && approver is not null) {
            Record("pairing_approval_intent",new {label,method="device.pair.approve"});
            await approver.SendWizardRequestAsync("device.pair.approve",new {requestId=request},10000);
            client.Dispose(); client=Client(path,true,interactive);
            if(await Ready(client)) {Hello(label,client);return client;}
        }
        Record("pairing_not_ready",new {label,pairingRequired=client.IsPairingRequired,requestId=client.PairingRequiredRequestId});
        client.Dispose(); throw new SafeFailure("pairing_not_ready_"+label);
    }
    static async Task Provision() {
        using var control=await Paired(ControlPath,"provisioning-control");
        using var allowed=await Paired(AllowedPath,"allowed-app",control,true);
        var identity=new DeviceIdentity(ReadPath); identity.Initialize();
        if(identity.DeviceTokenScopes?.SequenceEqual(new[]{"operator.read"})==true) {Record("readonly_already_provisioned",new { scopes=identity.DeviceTokenScopes });return;}
        using(var initial=await Paired(ReadPath,"future-readonly-v2",control)) { await initial.DisconnectAsync(); }
        using var candidate=Client(ReadPath,false);
        if(!await Ready(candidate))throw new SafeFailure("device_token_bound_candidate_not_ready");
        Hello("future-readonly-device-token-bound",candidate);
        Record("self_rotate_intent",new {method="device.token.rotate",role="operator",scopes=new[]{"operator.read"}});
        var payload=await candidate.SendWizardRequestAsync("device.token.rotate",new {deviceId=identity.DeviceId,role="operator",scopes=new[]{"operator.read"}},10000);
        if(!payload.TryGetProperty("token",out var tokenProp)||string.IsNullOrWhiteSpace(tokenProp.GetString())) {Record("rotation_no_token",new { responseFields=payload.EnumerateObject().Select(p=>p.Name).ToArray(), tokenDelivery=payload.TryGetProperty("tokenDelivery",out var delivery)?delivery.GetString():null });throw new SafeFailure("self_rotation_token_not_delivered");}
        var scopes=payload.GetProperty("scopes").EnumerateArray().Select(p=>p.GetString()!).ToArray();
        if(!scopes.SequenceEqual(new[]{"operator.read"}))throw new SafeFailure("self_rotation_unexpected_scopes");
        identity.LoadExisting(); identity.StoreDeviceTokenWithScopes(tokenProp.GetString()!,scopes);
        Record("self_rotate_issued_and_persisted",new {role="operator",scopes,tokenPrinted=false});
        await candidate.DisconnectAsync();
    }
    static async Task<int> Count() {
        using var http=new HttpClient();http.DefaultRequestHeaders.Add("x-proof-control",Config.ControlToken);
        using var response=await http.GetAsync($"http://127.0.0.1:{Config.BackendPort}/control/status"); response.EnsureSuccessStatusCode();
        using var json=JsonDocument.Parse(await response.Content.ReadAsStringAsync());return json.RootElement.GetProperty("count").GetInt32();
    }
    static async Task CheckReadonly() {
        using var allowed=Client(AllowedPath,false,true); if(!await Ready(allowed))throw new SafeFailure("allowed_reconnect_failed"); Hello("allowed-positive",allowed);
        var before=await Count(); var audio=await allowed.SynthesizeSpeechAsync("PR1915 synthetic authorization positive control.",allowed.SessionMutationConnectionEpoch!.Value);var after=await Count();
        Record("allowed_synthesis_positive",new {provider=audio.Provider,mime=audio.MimeType,bytes=audio.Bytes.Length,backendBefore=before,backendAfter=after,delta=after-before,played=false});
        if(after-before!=1)throw new SafeFailure("positive_counter_calibration_failed");
        using var read=Client(ReadPath,false); if(!await Ready(read))throw new SafeFailure("readonly_reconnect_failed");Hello("readonly-reconnected-no-shared-token",read);
        if(!read.GrantedOperatorScopes.SequenceEqual(new[]{"operator.read"}))throw new SafeFailure("actual_grants_not_readonly");
        var status=await read.GetSpeechStatusAsync(read.SessionMutationConnectionEpoch!.Value);
        Record("readonly_tts_status_success",new {provider=status.Provider,status.IsReady});
        before=await Count();bool preflight=false;
        try {await read.SynthesizeSpeechAsync("PR1915 forbidden synthetic speech.",read.SessionMutationConnectionEpoch!.Value);}
        catch(GatewaySpeechException ex)when(ex.Failure==GatewaySpeechFailure.PermissionRequired){preflight=true;}
        after=await Count();Record("readonly_production_preflight",new {classification=preflight?"PermissionRequired":"UNEXPECTED_SUCCESS",backendBefore=before,backendAfter=after,delta=after-before});
        if(!preflight||after!=before)throw new SafeFailure("readonly_preflight_failed");
        before=await Count();bool denied=false;string classification="unexpected_success";
        Record("readonly_raw_rpc_intent",new {method="tts.speak",purpose="real Gateway denial independent of Companion preflight"});
        try {await read.SendWizardRequestAsync("tts.speak",new {text="PR1915 forbidden raw synthetic speech."},10000);}
        catch(GatewaySpeechException ex)when(ex.Failure==GatewaySpeechFailure.PermissionRequired) {denied=true;classification="GatewayPermissionRequired";}
        catch(Exception ex)when(ex is not TimeoutException) {denied=ex.Message.Contains("operator.write",StringComparison.OrdinalIgnoreCase)&&ex.Message.Contains("scope",StringComparison.OrdinalIgnoreCase);classification=denied?"GatewayMissingOperatorWriteScope":"finite_unclassified_rpc_failure";}
        after=await Count();Record("readonly_raw_gateway_result",new {classification,backendBefore=before,backendAfter=after,delta=after-before});
        if(!denied||after!=before)throw new SafeFailure("readonly_raw_gateway_denial_not_proven");
        File.WriteAllText(Path.Combine(Output,"B-summary.json"),JsonSerializer.Serialize(new {passed=true,actualReadonlyScopes=read.GrantedOperatorScopes,provider=status.Provider,allowedControlBackendDelta=1,preflightClassification="PermissionRequired",rawGatewayClassification=classification,negativeBackendDelta=0,ephemeralSharedTokenFallback=false},Json));
    }
    static void CreateProfile() {
        var identity=new DeviceIdentity(AllowedPath);identity.LoadExisting();if(string.IsNullOrWhiteSpace(identity.DeviceToken))throw new SafeFailure("allowed_identity_not_paired");
        var registry=new GatewayRegistry(Profile);registry.Load();registry.AddOrUpdate(new GatewayRecord {Id=GatewayId,Url=Url,FriendlyName="PR1915 disposable proof Gateway",IsLocal=true,SharedGatewayToken=null,BootstrapToken=null,SetupManagedDistroName=null,NativePackageFamilyName=null,NativeRuntimeContract=null});registry.SetActive(GatewayId);registry.Save();
        var settings=new SettingsManager(Profile) {GatewayUrl=Url,AutoStart=false,GlobalHotkeyEnabled=false,HasInjectedFirstRunBootstrap=true,UseGatewayVoice=true,NodeTtsEnabled=true,NodeSttEnabled=false,EnableMcpServer=true,EnableNodeMode=false,VoiceTtsEnabled=false,TtsProvider="windows",TtsKokoroAutoDownload=false,EnableManagedLocalGatewayAutoRepair=false,NodeSystemRunEnabled=false,NodeCanvasEnabled=false,NodeScreenEnabled=false,NodeCameraEnabled=false,NodeLocationEnabled=false,NodeBrowserProxyEnabled=false};SaveSettings(settings);
        Record("fresh_app_profile_created",new {manualGateway=true,managedWslOwnership=false,nativeOwnership=false,sharedGatewayCredential=false,useGatewayVoice=true,tts=true,stt=false,node=false,mcp=true,automaticSpeech=false,autoRepair=false,autorun=false,hotkey=false});
    }
    static void SetProfileRelay() {
        var registry=new GatewayRegistry(Profile);registry.Load();var record=registry.GetById(GatewayId)??throw new SafeFailure("profile_record_missing");
        registry.AddOrUpdate(record with {Url="ws://127.0.0.1:19516"});registry.Save();
        var settings=new SettingsManager(Profile){GatewayUrl="ws://127.0.0.1:19516"};SaveSettings(settings);
        Record("task_profile_relay_selected",new {port=19516,identityPreserved=true,managedOwnership=false});
    }
    static void SaveSettings(SettingsManager settings) {
        try {
            // The internal production persistence entry point is invoked only to surface
            // actual save failures; no grant/auth property is reflected or changed.
            typeof(SettingsManager).GetMethod("SaveOrThrow",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(settings,null);
        }catch(TargetInvocationException ex)when(ex.InnerException is {} cause) {
            Record("settings_save_failure",new {type=cause.GetType().Name,hresult=cause.HResult,dependency=cause is FileNotFoundException missing?Path.GetFileName(missing.FileName):null});
            throw new SafeFailure("settings_save_failed");
        }
        if(!File.Exists(Path.Combine(Profile,"settings.json")))throw new SafeFailure("settings_file_not_persisted");
        var persisted=new SettingsManager(Profile);
        if(persisted.GatewayUrl!=settings.GatewayUrl||persisted.UseGatewayVoice!=settings.UseGatewayVoice||persisted.NodeTtsEnabled!=settings.NodeTtsEnabled||persisted.EnableMcpServer!=settings.EnableMcpServer||persisted.EnableNodeMode!=settings.EnableNodeMode||persisted.AutoStart!=settings.AutoStart||persisted.GlobalHotkeyEnabled!=settings.GlobalHotkeyEnabled||persisted.NodeSttEnabled!=settings.NodeSttEnabled||persisted.VoiceTtsEnabled!=settings.VoiceTtsEnabled||persisted.EnableManagedLocalGatewayAutoRepair!=settings.EnableManagedLocalGatewayAutoRepair)throw new SafeFailure("persisted_settings_verification_failed");
        Record("settings_persistence_verified",new {exists=true,urlPort=new Uri(persisted.GatewayUrl).Port,persisted.UseGatewayVoice,persisted.NodeTtsEnabled,persisted.NodeSttEnabled,persisted.EnableMcpServer,persisted.EnableNodeMode,persisted.AutoStart,persisted.GlobalHotkeyEnabled,persisted.VoiceTtsEnabled,persisted.EnableManagedLocalGatewayAutoRepair});
    }
}




