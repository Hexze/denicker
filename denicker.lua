plugin = {
    name = "denicker",
    displayName = "Nick Alerts",
    prefix = "§cDN",
    version = "1.4.0",
    credits = "",
    description = "Detects and resolves nicked players, and tracks nick changes on your ignore list"
}

-- State
local parsed = {}
local nickDisplayNames = {}
local pendingChecks = {}
local teamDataReceived = {}
local resolvedNicks = {}

local ignoreEntries = {}
local pendingBlocks = {}
local listParse = { active = false, totalPages = 1, pagesSeen = {}, names = {}, timer = nil }
local syncing = false

-- Config helpers
local function getConfig(key, default)
    local val = starfish.config.get(key)
    if val ~= nil then return val end
    return default
end

-- Config schema

starfish.schema.section({
    key = "alerts",
    label = "Alerts",
    description = "Configure the plugin's chat alerts.",
    defaults = {
        alerts = {
            enabled = true,
            audioAlerts = { enabled = true },
            alertDelay = 1000
        }
    },
    settings = {
        { key = "alerts.enabled", type = "toggle", default = true, description = "Enable or disable all chat alerts." },
        { key = "alerts.audioAlerts.enabled", type = "soundToggle", default = true, description = "Play a sound when an alert is triggered." },
        { key = "alerts.alertDelay", type = "cycle", description = "The delay in milliseconds before sending a nick alert.", displayLabel = "Delay", values = {
            { text = "0ms", value = 0 },
            { text = "500ms", value = 500 },
            { text = "1000ms", value = 1000 },
            { text = "1500ms", value = 1500 }
        }},
    }
})

starfish.schema.section({
    key = "modifyDisplayNames",
    label = "Label Nicks in Tab",
    description = "Enable or disable tab suffixes for nicked players.",
    defaults = { modifyDisplayNames = { enabled = true } },
    settings = {
        { key = "modifyDisplayNames.enabled", type = "toggle", default = true, description = "Adds a label to nicked players in tab to indicate they are nicked (and show their real name if available)." },
    }
})

starfish.schema.section({
    key = "showUnresolvedNicks",
    label = "Unresolved Nicks",
    description = "Enable or disable alerts for unresolved nicks.",
    defaults = { showUnresolvedNicks = { enabled = true } },
    settings = {
        { key = "showUnresolvedNicks.enabled", type = "toggle", default = true, description = "Alerts for players who are nicked but could not be linked to a real name." },
    }
})

starfish.schema.section({
    key = "ignoreList",
    label = "Ignore List Tracking",
    description = "Track your /ignore list and detect nick changes.",
    defaults = { ignoreList = { enabled = true, sound = { enabled = true } } },
    settings = {
        { key = "ignoreList.enabled", type = "toggle", default = true, description = "Alert when a name on your ignore list changes (a nicked player's new nick becomes visible)." },
        { key = "ignoreList.sound.enabled", type = "soundToggle", default = true, description = "Play a sound on nick-change alerts." },
    }
})

starfish.schema.section({
    key = "addNicksToCubelify",
    label = "Add Nicks to Cubelify",
    description = "Automatically add denicked players to Cubelify.",
    defaults = { addNicksToCubelify = { enabled = true } },
    settings = {
        { key = "addNicksToCubelify.enabled", type = "toggle", default = true, description = "Sends a message that cubelify will read to manually add denicked players to your overlay." },
    }
})

-- Known nick skin hashes

local KNOWN_NICK_SKINS = {
    ["4c7b0468044bfecacc43d00a3a69335a834b73937688292c20d3988cae58248d"] = true,
    ["3b60a1f6d562f52aaebbf1434f1de147933a3affe0e764fa49ea057536623cd3"] = true,
    ["19875bb4ac8e7e68c122fdf22bf99abeb4326b96c58ec21d4c5b64cc7a12a5"] = true,
    ["dd2f967eee43908cda7854df9eb7263637573fd10e498dcdf5d60e9ebc80a1e5"] = true,
    ["21c44f6b47eadd6720ddc1a14dc4502bd6ccee6542efb74e2b07adb65479cc5"] = true,
    ["7162726e3b3a7f9c515749a18723ee4439dadd26c0d60e07dea0f2267c6f40a7"] = true,
    ["10e62bc629872c7d91c2f2edb9643b7455e7238a8c9b4074f1c5312ef162ba22"] = true,
    ["4336ff82b3d2d7b9081fec5adec2943329531c605b657c11b35231c13a0b8571"] = true,
    ["173ec57a878e2b5b0922e34be6acac108372f34dace9871a894fe15ed8"] = true,
    ["7f73526b1a9379be41301cfb74c55270186fbaca63df6949ce3d626e79304d92"] = true,
    ["7d91aee3b51f3f8d92df52575e5755d97977dcdfb38e74488c613411829e32"] = true,
    ["8e42e588e1d09ce03c79463e94a7664304f688caf4c617dbcbca64a635bbe79"] = true,
    ["8f1f9b3919c879f4ec251871c19b20725bc76d657762b5ddfdf3a5ff4f82cb47"] = true,
    ["989bc66d66ff0513507bcb7aa27f4e7e2af24337c4e7c4786c4630839966fdf7"] = true,
    ["bdfc818d40b635bcd3d2e3d3b977651d0da0eea87f13847b99dc7bea3338b"] = true,
    ["5841684ec6a1f8ba919046857dac9175514fef18a2c9395dc3e341b9f5e778ac"] = true,
    ["211e121448c83125c945cd238dc4f4c5e9a320df5ee3c8c9ad3bb80c055db876"] = true,
    ["3cce5c4d27979e98afea0d43acca8ebddc7e74a4e62480486e62ee3512"] = true,
    ["68d98f9a56d4c0ab805c6805756171f4a2cdbf5fa8ce052a4bf4f86411fb080"] = true,
    ["e2629467cf544e79ed148d3d3842876f2d8841898b4b2e6f60dfc1e02f1179f3"] = true,
    ["6162abdfb5c7ace7d2caaabdc5d4fdfc32fb63f2a56db69f276167dffce41"] = true,
    ["af336a55d17916836ce0ed102cbdb0fa6376544971301e0f28beb3899c649ff2"] = true,
    ["1580729b12e1d6357e7eaa088fbf06ba2c8a2fb35b0ba4c5451937d3f134ca9"] = true,
    ["1f72e604cdb4c49f7106b594ac87eff3ed6a1999255437241f57d28c45d103f"] = true,
    ["542a699fe314b9f747eed89b9cae23fdefc27684f6c13dc4a29f5d057cc12d"] = true,
    ["b2a4cd136505395a876113a800aa8ec15761ca3d945b57e0d0dcdcfeafd7a6d9"] = true,
    ["907fcce8c3a8d337a6aff226847e3cc7c9bb6bd02f43be1b7c71b3dcd244e11"] = true,
    ["62a6c3e6b8cbd4fbcb5866289642bb5b5a90dd16e2c28dc054c9d248943834f9"] = true,
    ["173481eb7f2157a5ad79ec765d36be5736395b72ee519185e23f436ba15185"] = true,
    ["9ad4ffb57819e7ff633f60b5901e44a3570573ad4d453075b72ae2cbd23c8a6d"] = true,
    ["8c064476ed9de9ca437cf869127c61a945ea6c308e9b25e4a991bb252c6d754d"] = true,
    ["9ddd647a59a93c23ce49cece35f7529985ee40d0ca7ead6a1e3fe0f97b286162"] = true,
    ["c56ab25347aa70f406a85d221da104c5ff05d2a1866a1b57dc1ab4f5feb97"] = true,
    ["7dcb1d264010bfac568d19e9baee3c2a2aaa729d6cf335b9cf62d2fb2f4c813"] = true,
    ["fd22ca2c137a6ecf6a4366eb1f2c8a6b173220b295abc1ae13cedf93dabdbf3c"] = true,
    ["7245bc1d62123b6f8c954cf08be76c9c0d23e778ca9843935a24782c8b2bab"] = true,
    ["721d9bc16854e75bad69fc7529e3f4c82f32a4715f219697f413c67115a93"] = true,
    ["e1aa418bd0b4f4d37d6853b7c577eac34034d2f64b6415ff653132f4ca66cd7"] = true,
    ["c2159fdfe7ef9f12269e2791ebc5aca8e787506b28bfc69747ccf12671261afb"] = true,
    ["8362ff7077a326747210c56031dc46a141f25454b27873395eda6483d55df"] = true,
    ["6845756829b6bca516b5bf9251ae31c79cd6ddbc3c57f119370b0ccd8d6f5a1"] = true,
    ["b77b40e51c7562e523efb0c0f94a616da97c1f485fd8b4a4ac9fb37561812"] = true,
    ["48b34cc77a18dfa0ebb54f93c3c31779769f519f41b5153c1869aedec9965b2"] = true,
    ["44d65b5b742333fa051b81b8365155618d4231becd9393283ec639b2f12b7f93"] = true,
    ["dff36d1281f862f8841d2b84ce17c560e45cd0b3fd879c78c13d26b7c7f7cbfe"] = true,
    ["1cdeb260f0b31796aca16be0c79ea0169b6f6542fef743c09c4238ad2114a49f"] = true,
    ["1ab96446ecc368e4c685239fb6d14f7adbf337fb343da95285eec68dd79c4a"] = true,
    ["7e9437c77b2529da8dbb0545f2898e9a2d12e667f8e6f69f051ced32acfde"] = true,
    ["b5f0d648162c98c6ee9cb31c4e5cead456dd105a37f7ce8a7a09d384a47b8b2"] = true,
    ["7f9712869fb1ffbd4905342aca6b7a4f5e47ee9ea7dae5e752c7b9e9bbcea"] = true,
    ["5485ef7d262e19a65756ec94338777f93b16f64da2783189d0ee34b816b357"] = true,
    ["869b276cbe44c4a5918beb106e625ae36f829e7c7bcdfad8b67565f48430b199"] = true,
    ["243ad02c2f5bf1a4b8225a1f6243d507e707fda68237f2aa738467c956be10"] = true,
    ["dd80f354e47a8b66bddb43ff38d972487aa1105d1eebdb7a26844c140d888e0"] = true,
    ["32aba3b2955a782f0a3a37bfa9c4173919bdc4827c99bee5670169ec4e181dc"] = true,
    ["c9939c9d2d9e5e5fb689b12d89e9edf08c915866b7661545fe46e88ab1551"] = true,
    ["c61aec3d73110435b3c549f7bb70d4aa6d6e6c404590b34be63e6ab42c2946"] = true,
    ["c96522d14a7a21f59fc2c66ef82fbe62263c9d7d064f823b7c1a614e409099"] = true,
    ["5a75720a749dca3fee845d6d7e9b2234542f1a2d7d948f040c5ca3e493f5e4"] = true,
    ["4a213a331b92693ec8f534f627803ac8492df0916b70a762e28aff6a5d8ea2"] = true,
    ["c149f0fe3a696fad6fd6ad7858ff788b6d15129207b5f72b0d7d7f983e1b"] = true,
    ["6c175165d75062a323c5865916162ce7eca5e6ac224440c8b0536c96530d33a"] = true,
    ["acf665de64faf18cbfd1d13598fd4552566c878fbc3716f52587e2cbae44b9"] = true,
    ["ff167fcbb98ecd6377905add5c15459e3fb815a0b7c9142e8037a818945630e"] = true,
    ["3e8a56d37decce24f73e3e97e67812a2f5a1384a525f4c0e58cd3fdeffc38"] = true,
    ["4d6e309a40b631ec6cb5be74e22b883da452f43acf4e834f43c1cb25c8f82a"] = true,
    ["7417341979bb41714df892d4994d63347006be8bd7f2cfb65b826d2b21172"] = true,
    ["fe74c2edd110608e523ce6b6b31f528cb38a122941ede2d68d61ba52bd6802e"] = true,
    ["04426382d98452d90ef2cdb492af67853ca8542972595351acc6cbf88f51532"] = true,
    ["c35dd24dc529b664504bfd3315b3fe8ca9c6c9b9fe1e84ce6aea216ef7bd3"] = true,
    ["d2498d91a41fdb77f58c9da73073cc3f287b93ee12ccbfa6473d55019454b1d"] = true,
    ["3fca4000b6c9b5c7d57f29245bb9ee00af282e351d697a44031d15a1384eb3e8"] = true,
    ["f3e399b37b4fba7d2fd0ed14f8a6820131d6c9a355282704c59796f092677542"] = true,
    ["1561ee2ea67346c667b4e96d85847b7b51372b605fe34ae046c8c0d0d2973d"] = true,
    ["40f836d124597ab614e97ab9bae81bcfacfb9a5cb87b8ce9fc50e5ab93c53dae"] = true,
    ["52ff1cf6537438f4aff7c2cdcdc84cca8f42f9aa264913827981ace5876f71"] = true,
    ["8983c344fe3bb69d16caa51766a5bf371ec9075496a061334db9f9a44711"] = true,
    ["76acbc4d98a2deab2b2b8e7798d5b9ae54e1d5710c9b0e93c243461405d4519"] = true,
    ["b4c815e8e24ecc26ce18a35a938a5d8b6f96e9c8467841be37699d83e43d"] = true,
    ["16b5b6a89aa283548411eef311b2ab46216a7b0538452b249386895b917cf2"] = true,
    ["5ff1fd2453f6d85961de8976bce16c5d514e38ad7f846e99317ca4a3b5889"] = true,
    ["1b144c7532ec233ffb5c52e69e3d98be12d52481fd5113703f21e1ec850b6"] = true,
    ["64316ffd3ede6158b3eb421b97cbf9b82dd93e08d54b3f9f0105c75f134f89c"] = true,
    ["b6966498a988780cd1dcf4ea059eeec6497fe14b95c32470bc6d99b17ff1"] = true,
    ["b9ec71e4727fde6edef0d08f25561c4ba6eb21583fd9fae443e566c79d88e160"] = true,
    ["3385c509e1b649552c750dc23c344d24d158df94f6d8532377a9b726462bc05b"] = true,
    ["59f87bef785eddc72f2289b8482375266bc3ceed365c270c5ef7f835df39"] = true,
    ["27d4d629ac756da03d894556535bcca033fdaf172e69cc772262b43918ede351"] = true,
    ["af43feeb32559878e0561c87f8f35c9812973bf27661d874bf68bb569b333f45"] = true,
    ["ef1f3805eb46853b22559404b373c54b12453c4882abf3dd7673f5869be4cd"] = true,
    ["7265757c8a5a826f9e2b68e4631fee33e74dcbfcd9e4c744360186f4ff58fa1"] = true,
    ["3bf9314d6f78711c93d895519bc620a8176819551dc1d498aea840f32cf0d917"] = true,
    ["ae97b72b9972d5db2516ceda54c6837116c2c52e75763749de9949aaab95d0"] = true,
    ["6512d4661323db375b829bf2e090f7c3a277f95d3a5613ae59a06d9a9a270"] = true,
    ["bf948ef3d865729d4120179087c0323a4cb913119932aa620dd9accef7d528a"] = true,
    ["bb9688ec3a8fb8f18887377bd5be94a56fafb267d870c0532c356cc35adc"] = true,
    ["4097a9b1113fa753d37d613ab9e118f0d05d3f5276f965f6466bb25d313a0a9"] = true,
    ["40952ce63957766d68819e9e033429db2f9a472b3646d856e8b839088de699f"] = true,
    ["59c13c5c833d4205fb899fe6a329f136c5c67ce0dd86efb834684686ead2d"] = true,
    ["762b16ce467a4096e188f9c12351e66fce8ef1e18b6e9788befe4666c68876"] = true,
    ["80516a7b5faf2cc796650c51c167773ba8c8e73e94b10d96d3e9d827dd63c5"] = true,
    ["5a956dc2631e54a3cb62d31390226b5cc052432fc7b9261da4bf6420f8d7e8"] = true,
    ["156c183d1064d9d72e25de3945ef16483c15eb06b6c87396ab4ba1f8e9b6df"] = true,
    ["1d387e3e5b89925ce6519cfb4378af11abed6e4b7ae3491f93048971a2e80e7"] = true,
    ["8fcdcc72bfd5192d752d1a5eac7c11115c9aa43d574dfa85f99f2896c9b15"] = true,
    ["b6557aa1aaf5fe97745da389ab69473ef9f5ec31960be2860a5c8bd6ed37"] = true,
    ["a191322292ab595ff53c704b85f514f5b9f45470332ac2719eb85e92df4023"] = true,
    ["93e15c711b3a37d5634a1b629cb9e43f793f297dd3369c2bdd9b4bba80fa6b"] = true,
    ["489fd1a12c42e0fed383e9d23bacb95815fb752213849ddaa8b5893ac7eba24"] = true,
    ["fbd1fa49884dacaed4cc4650d23bfea4dc7a89dce8d90a2e27acfb712e8f8"] = true,
    ["daa35aa45c2d7092e359962e79d11842ed18ce499aacff22c5871662f7a69dd"] = true,
    ["447374bbeadeaa36684d3f68eb46bed5b7d145a206d5a54b9c12382d6b1f9dce"] = true,
    ["9c8f4d6466382820536e82842a162615c2e7d2316afc59264a9c3ede"] = true,
    ["997eb6a7b37bc8924ed341a4a0a356112b620bbc121b5ce27e692a535d2df81"] = true,
    ["adc9c2fd56f6698f5807012e4dd2e785e5efe1e6799b47cd1c3bdb1c05eda3c"] = true,
    ["2d13cdd15b5673a27a63c04226e3b2b3639ac27fb853d1a146a239496da1ff"] = true,
    ["238580ddf446509b4c84e829b39a8b2f72ab8cd649dca6886405dd2ad2dcd5"] = true,
    ["241c4fdecb52afd81b24993b5a7e6c715f375d94f4eafab39a60bb2b5050e9"] = true,
    ["d2447fe1ee25c2476525e78aa71bd2f56bdec3b5f829215650642563698d272"] = true,
    ["f515cc3ace7a74afe76e41c117dace9f278b63c1829d30b246bd7d73584cf2"] = true,
    ["9691b4eada776b725eb2a5fdda77af65b87ccfde6ccb76c75fbe4da347723"] = true,
    ["344f6ae0fa81aadf8a2197e656cb8e696d18f12e2a87ab42c41b64b61c688"] = true,
    ["6b76f913d7c02718c7cf9a8087db3dc246d9eb89febefd28abfd59226559548"] = true,
    ["eed8565e62768584c3a933227e1747165dd86e3942a93f52e4285ba65cd2662"] = true,
    ["8fee25beac53be9a196b5319e9887eaff50cb19a61ad5d88bb57fe431c8a8"] = true,
    ["e32379103e70b548a716a1c8d477b611c44c6d1925e978f1164362f22564b9"] = true,
    ["c8424766a87919285dd9f92e4c8868de558d87c739d76668b532f7c21a490"] = true,
    ["ad369862824c34b9354edc9cb14832364dc74cf867863210c1a83dc3ebcd22c3"] = true,
    ["a17d731aef41184853bafa292fa9f46c6c56912cdd1bb4cd43e53c88ba82cc6"] = true,
    ["ff642bf35a3e622515bb1f20356534fc3f24316b3eb170f477f336ec26edf9d6"] = true,
    ["dd222e15fa6d522d9bc3a674d1a9327bbee733b396246e40af1fce716bef9b"] = true,
    ["7fd6bf7bc58c661dbef8b8896eb2ccd31229a3e8b09e54d769c1e46242348277"] = true,
    ["4e5223efd125cba238eea12334f9e856718842281d7f865db3c6d577ed5e084"] = true,
    ["689026f3bf84461b773a3e7915da121dde4a3371598a8431cd5e8951ea549"] = true,
    ["80c86c1d62b71928d6251ef238434e226fa9fe3041964625d8a0e550d8f528"] = true,
    ["d275c5282d3ce248ecec75b82a44c2e70497c76565c993618316ca12a1efb8a"] = true,
    ["4c232f62387b2ac54c371beaaa0577fe7778a3c6954b34914c3e016b84f6f46"] = true,
    ["2ecf8d5923446aba9eeef5a24848b84b20bbc37c80ca62e9e664375c24dc7077"] = true,
    ["d5fab8a6fc9ec343f7ccecd86a0f5cc339d11a02c8fb0ba1ed5cb446d01ae0"] = true,
    ["ddeb44d8f85ee1b918dcd231eb62887e2e2df63df8c91d11461111f710c9f2ac"] = true,
    ["c25c40b36da47d6a982c86a319d6fe5e4916df411fbbf656451bd6049d6d179"] = true,
    ["5fe8b3813cf0c55cdf2c97789735d62085767323cd9af8da804669592ac45f"] = true,
    ["7cbe75103d02c10dd410fc5760139212fbeda8d91ee752e53e4674aecfa30"] = true,
    ["35873a599e65596b99080d86f5b5ecfe162a8235a136bb4990fb8e2325965b"] = true,
    ["f813e90a33dce8bca6a6c688683706498e1f2aaec8530c481c2a80faa82ddebc"] = true,
    ["99a5daa3fe44c414ca8f4324c36bced2afe6d962a580842d8a36c5d9c1b8be0"] = true,
    ["672d94becd9f61dec864a8232692fb1c54ff4676ade457ae6847f7d9d954a8d"] = true,
    ["b0a74cd03493521b451cbf256775e93809a203672e837e0eb46c590e5f0928f"] = true,
    ["f3a01fd5a6267170ff7c6526d3a9ee4ee4403e036955f902c9414c064d9449be"] = true,
    ["bfd4e3b0527bd94824e530968f2281ce8e3dd9a3f6b73fb23e6cc15b7c79d2c"] = true,
    ["4fda29ceab6ca457da30882493c5129287277895ebd3f244456126666a6"] = true,
    ["79b7861ac71a511be1b88823549fbbbbc8a300dccc0e873322ea2a7859d686cc"] = true,
    ["3debc1619533fe5f011783e43e526efad44bf49ace9e5ca10badd7f55e069"] = true,
    ["dbc1c832b4919315df977aedc7ece84d9aabef8823cc9de5ceee5129b1728"] = true,
    ["7a27c712e9446026aa38afd114d76cef0b96bdbfe58adbf73a9a9149684eac3"] = true,
    ["b78e4089143163c32291d6365e715e1b42806a40784ff93b8737947c7687e9"] = true,
    ["3a3d66c09223d0899b896487505fda388584941ec946534d2a9e277133fe02e"] = true,
    ["1ae5861b10c43426dc4345aa49585d818886a1fa4599c8ada0b2fcbf69b81"] = true,
    ["a7924326aca6415f34b017573996f333ad1c8db9bf46d4fa216493faafbc9fd"] = true,
    ["62cc348490c1d2bf32daed40eae64bf812c3ba23abda3653a1335af6f2123b"] = true,
    ["c9b2b946ab9aebc76084157641aceed34e83185d958fc2f225c2595c8171d6"] = true,
    ["81895e92fc1552fe1dcd531f6775e1266146b75812c58795a1b0a3bef922b79f"] = true,
    ["8569245371edff63a26913a972f2c44fbe41f75e42668a72599759cf452f3a"] = true,
    ["2470257f2b1ea354f4a1c5e0e1ee207d162f669a83e440a913cd87f58f52ffd9"] = true,
    ["1670d1f3de92402e51e780b2e6699dabbc79fb44dca1c273f5cbde64258aa"] = true,
    ["dc3938ebca030fe937c77b9876d456e19e9b6588f3ee8ec993bace98ccae4e"] = true,
    ["1ad471136cdf5e9dec7b30c841f2b9af1aab09b9f369fa24aa52a98f4b0afe1"] = true,
    ["c828ea469bef8c84eee8e9abf66788c7991789d8f3a21ab460789a0b14884"] = true,
    ["16c63d6591c8e7e3a1b8825e43bb8dc8ac561ab567a9cda57cf783031e0"] = true,
    ["62604b8b7df3da89a0a85ed8152073da59f31774cdcfec66951edd572a72957"] = true,
    ["4b28dc744eb31957b74a14bcfc2320b451f5b6859a158fd8bab28dd873f71b"] = true,
    ["3d4a203011d23899e4f02065324b4c9e97228f2ab2cef1eb366c8edbaad26d"] = true,
    ["b6ed84678adf2445348963fc343a6f44e8631a1d7fd25f377d824e9bde37e"] = true,
    ["34f889c53b26a7b68569a51be9a5d17d3fca371df6dc615183e2b437530"] = true,
    ["b7d33aa3cf94603b6bbaccdda885c33bdba3baf6f866b9c1dc64816cf47e7fa"] = true,
    ["bd2730d152b782f5e6f26e5d22f49d3da81ada8cb193fecd37189a72b9a7c"] = true,
    ["49e3bd98686d1146b9337c9652899a12f28fe59e42f123578e8981652510e5"] = true,
    ["4c4d84cc6798da26511812353857e7630544ecbb93a7d9a5a44e0a8bddf3"] = true,
    ["de915d709d818429c09838c6341ce6c4abf41e450def2dbb4c12adee5745fb"] = true,
    ["f1d8494d382feb5e7434daa2fe553b4d6b51269717cd12309d331399efdbbd49"] = true,
    ["c41043fb371ce1d6bc2b5e3c38c116177a71aba9c2e9511188f9e15955131"] = true,
    ["a5e77eca3a8571b6ea72a2d1d41429323c610d35477191d5191faa9745d772"] = true,
    ["f42d8249035be11d50ef8c2a947d1ffe3eb8d91989de5b27748190eb231295"] = true,
    ["2e24edaf3df936127c1be1097bc798411719489a1652139ebd6f8dd21fda71b"] = true,
    ["14ea486fef4c37c771f23968df9d47358111d3cac57c458c57b6a2c7dc9970"] = true,
    ["7dc27a418be63cd1ece8d2daf106c5b369db846c6c141d2bde4d81c83eff"] = true,
    ["f911f9329b391d8b6e30d55ab9f20608d620d682c9327514b5ab9d1b7ed360d3"] = true,
    ["c0554e6189ce7ba79de273dcac358f2985771d3e3cec7ff8b4c953bf6d5c5"] = true,
    ["f60648e541171fb69121794cc8894c3168ba841c897cbb457819172d9df3"] = true,
    ["7c5aeae0e15227404b1f1c59c93e9ffce83c7433feb5649ecc2ddc1af6e2c7"] = true,
    ["9960335e7981e3c82b03a59bce8aad04b893efc9928e825498199d59627079"] = true,
    ["579a5713ed8affbfe8bbcd432def758ec4a31647db4f7dda4df7535a3fa0f58f"] = true,
    ["7fb832fa27791731e34a1adaf6f59c1a95e6e5aa46d528f6c2975d668bc1"] = true,
    ["cae2c0eb1730e11888e3f4dc133e9c5fd1434beb19b1616b026412fafc8e87"] = true,
    ["7ca423e35c767d5844f8bb9a3c949710e8615847e3f6db117591ce53c30f9e1"] = true,
    ["cf9de3c33c4b523248fc7dc23f18c551f1d2740cfeb162674aad031852e"] = true,
    ["f4254838c33ea227ffca223dddaabfe0b0215f70da649e944477f44370ca6952"] = true,
    ["fd41e45153cb159af3d2b3d0e4210969fc4a6402a327c5ab6d1f6981ceae7929"] = true,
    ["6437c4b8eba97a3f79a49074d8c9c6c7ededabffe2896161256d426014f52dfc"] = true,
    ["8b1ce430410e2416c1c0ae1ad2b91621e128b9c8a46e32dfee9a6e777eab6cf8"] = true,
    ["1e1408a4152663ccd1169965eabd5815216913bf9f9374d499ed3160a562cef9"] = true,
    ["e814f4ac1be28dd2ee5d6d297265d2efac52c36035a60bd919961914ea226ef"] = true,
    ["8958ea6b50dbb139ec56c20fa3d61d4902c30d4ee234d8009180bd9c37f33708"] = true,
    ["a7556d263c98a1d3b12236b56f613c516d91c755d4d7555eff0788da9c134f2f"] = true,
    ["6e0b2d4281ad9a090037ef0985fc0667e43c4762c083d34daaa6cd05d5e53055"] = true,
    ["7ae4fce4ecdfcf9e27e8723061fe43236ec937004cd0e016c7fd924587a34c5d"] = true,
    ["adcebc4e9a583d84ee7083b5540b8de8499f9ed4e02619213219c2c6eb081821"] = true,
    ["c6e4f799a1019320407a035ee54350b3a507523c7d5625f13b372a7b215402c9"] = true,
    ["23c7a66adf72ebe7338b23a34e5bf02827433c805e8b63c2a19ed9617df26b2f"] = true,
    ["81280cc515d765b001c9f628a4f488b1a910effd38bc24e0b5aa64252e68068"] = true,
    ["2dc567c2c3ee555d22944a5d9238c3d27915f5076f5ced1687471afd0dc605d4"] = true,
    ["fb44f9b19f45f1356f9c5c85ff2137018068e50c84ff0b2ae7d9ce0f33629d34"] = true,
    ["52b273741996ce877d63a8651e94ba3c55fee196c34fd52b78c0aa06c5fd550"] = true,
    ["48cc9961ec54f340f0d35239562d92748e92c6e2d6aa7aac884c414ae949618e"] = true,
    ["a8485f852d273ab6223517c0d84c4c13f704ea5e40a7431c5012bb2e86250445"] = true,
    ["8fba7e9fa894246022930de1320368d013544d6953f192c62561c1423bb44dd5"] = true,
    ["3ef953f0f2d9bdc2d2156952d7aae3fb438216a47108cbf0a0348f26e018049b"] = true,
    ["2ab3f698e25c02439c7b2dbd7b6648e2ecb3ddcc34e638ed4d116b0b409aeb25"] = true,
    ["2585c58e856754f3d7e36f427caa95aab8ff19781a1ba645acb428e86452b5a0"] = true,
    ["99e3b82da73910648899e454691e68f8d15f276dc9aab1435feff8a047948a40"] = true,
    ["75867d2c0a93cc99e05a86d55637e7f47fef7c9f98a9e5158dc36dd1b414bd90"] = true,
    ["b283088987c25b6153bbc1261864bc1764985dc4dd94bd5ebe040f598f7c4d59"] = true,
    ["5b71b9a4ff7292f7c4955407a97acc93d2784620a53367117713bfa07d0909c2"] = true,
    ["b1732d69af0612111e8f15ccc105013fe2ce08c4c65b65833b6456e4f01238ef"] = true,
    ["519d503b6cd7565119361cf6b51ef8d294a951b4b512d2727f28b5cc9d784626"] = true,
    ["d2da19710b8a4171ac9b17984dd95d042d92742d72a74ba40450d7494a24321"] = true,
    ["1d9e8dafe7d87bb7cba7eb3d8d2d5bf58eab72ecdfdf9ecce3d1c03871c0"] = true,
}

-- Display names

local function reset()
    parsed = {}
    nickDisplayNames = {}
    pendingChecks = {}
    teamDataReceived = {}
    resolvedNicks = {}
end

local function clearDisplayNames()
    for uuid, _ in pairs(nickDisplayNames) do
        starfish.display.clearSuffix(uuid)
    end
    starfish.debug("Cleared all denicker display names")
end

local function setNickDisplayName(uuid, nickName, realName)
    nickDisplayNames[uuid] = { nickName = nickName, realName = realName }

    if getConfig("modifyDisplayNames.enabled", true) then
        local nickSuffix
        if realName then
            nickSuffix = " §c(" .. realName .. ")"
        else
            nickSuffix = " §c[NICK]"
        end
        starfish.display.prependSuffix(uuid, nickSuffix)
    end
end

-- Alerts

local function sendAlert(playerName, realName)
    if not getConfig("alerts.enabled", true) then
        return
    end

    local function doSend()
        local alertMsg
        if realName then
            alertMsg = "§6" .. realName .. "§7 is nicked as " .. playerName .. "§7."
        else
            alertMsg = playerName .. "§7 is nicked."
        end
        starfish.chat.send(starfish.chat.prefix(alertMsg))

        if getConfig("alerts.audioAlerts.enabled", true) then
            starfish.chat.sound("note.pling", 1.0, 1.0)
        end
    end

    local delay = getConfig("alerts.alertDelay", 1000)
    if delay > 0 then
        starfish.events.delay(delay, doSend)
    else
        doSend()
    end
end

local function sendCubelifyMessage(realName)
    if not getConfig("addNicksToCubelify.enabled", true) then
        return
    end

    local cubelifyMsg = "§cCan't find a player by the name of '+" .. realName .. "'"
    starfish.chat.send(cubelifyMsg)
end

-- Ignore list tracking

local function stripColors(text)
    return text:gsub("§.", "")
end

local function saveIgnoreEntries()
    starfish.config.set("ignoreEntries", ignoreEntries)
end

local function formatAge(timestamp)
    if not timestamp then return "unknown" end
    local delta = os.time() - timestamp
    if delta < 60 then return delta .. "s ago" end
    if delta < 3600 then return math.floor(delta / 60) .. "m ago" end
    if delta < 86400 then return math.floor(delta / 3600) .. "h ago" end
    return math.floor(delta / 86400) .. "d ago"
end

local function findIgnoreEntry(name)
    if ignoreEntries[name] then
        return name, ignoreEntries[name]
    end
    local lowered = name:lower()
    for currentName, entry in pairs(ignoreEntries) do
        if currentName:lower() == lowered or (entry.originalName or ""):lower() == lowered then
            return currentName, entry
        end
    end
    return nil
end

local function formatNote(entry)
    if not entry or not entry.note then return "" end
    return " §7- \"" .. entry.note .. "\""
end

local function ignoreAlert(message)
    if not getConfig("ignoreList.enabled", true) then return end
    starfish.chat.send(starfish.chat.prefix(message))
    if getConfig("ignoreList.sound.enabled", true) then
        starfish.chat.sound("note.pling", 1.0, 1.2)
    end
end

local function sawAllPages()
    for page = 1, listParse.totalPages do
        if not listParse.pagesSeen[page] then return false end
    end
    return true
end

local function processFullListDiff(listedNames)
    local listedSet = {}
    for _, name in ipairs(listedNames) do
        listedSet[name] = true
    end

    local appeared = {}
    for name in pairs(listedSet) do
        if not ignoreEntries[name] then
            table.insert(appeared, name)
        end
    end

    local disappeared = {}
    for name in pairs(ignoreEntries) do
        if not listedSet[name] then
            table.insert(disappeared, name)
        end
    end

    local reveals = {}
    for _, name in ipairs(appeared) do
        if pendingBlocks[name] then
            ignoreEntries[name] = { addedAt = pendingBlocks[name], originalName = name }
            pendingBlocks[name] = nil
        else
            table.insert(reveals, name)
        end
    end

    if #reveals == 1 and #disappeared == 1 then
        local oldName, newName = disappeared[1], reveals[1]
        local oldEntry = ignoreEntries[oldName]
        ignoreEntries[newName] = {
            addedAt = oldEntry.addedAt,
            originalName = oldEntry.originalName or oldName,
            note = oldEntry.note
        }
        ignoreEntries[oldName] = nil
        ignoreAlert("§6" .. (oldEntry.originalName or oldName) .. " §7changed their nick: §c" .. oldName .. " §7→ §a" .. newName .. " §8(added " .. formatAge(oldEntry.addedAt) .. ")" .. formatNote(oldEntry))
    else
        for _, name in ipairs(reveals) do
            ignoreEntries[name] = { addedAt = os.time(), originalName = name }
            ignoreAlert("§a" .. name .. " §7appeared on your ignore list.")
        end
        for _, name in ipairs(disappeared) do
            ignoreEntries[name] = nil
        end
    end

    saveIgnoreEntries()
end

local function processPartialListAdditions(listedNames)
    for _, name in ipairs(listedNames) do
        if not ignoreEntries[name] then
            ignoreEntries[name] = { addedAt = pendingBlocks[name] or os.time(), originalName = name }
            pendingBlocks[name] = nil
        end
    end
    saveIgnoreEntries()
end

local function finalizeListParse()
    if not listParse.active then return end
    listParse.active = false

    if listParse.timer then
        starfish.events.clearTimer(listParse.timer)
        listParse.timer = nil
    end

    if #listParse.names > 0 then
        if sawAllPages() then
            processFullListDiff(listParse.names)
        else
            processPartialListAdditions(listParse.names)
        end
    end

    if syncing then
        syncing = false
        local count = 0
        for _ in pairs(ignoreEntries) do count = count + 1 end
        starfish.chat.send(starfish.chat.success("Ignore list synced (" .. count .. " tracked)."))
    end

    listParse.names = {}
    listParse.pagesSeen = {}
end

local function restartListParseTimer()
    if listParse.timer then
        starfish.events.clearTimer(listParse.timer)
    end
    listParse.timer = starfish.events.delay(1500, finalizeListParse)
end

local function onListPageHeader(page, totalPages)
    if not listParse.active then
        listParse.active = true
        listParse.names = {}
        listParse.pagesSeen = {}
    end
    listParse.totalPages = totalPages
    listParse.pagesSeen[page] = true
    restartListParseTimer()

    if syncing and page < totalPages then
        starfish.events.delay(600, function()
            starfish.chat.sendToServer("/ignore list " .. (page + 1))
        end)
    end
end

local function promptForNote(name)
    starfish.chat.sendRaw(starfish.http.jsonEncode({
        text = starfish.chat.prefix("§7Blocked §c" .. name .. "§7. "),
        extra = {{
            text = "§8[§aadd note§8]",
            hoverEvent = { action = "show_text", value = "§7Record why you blocked §c" .. name },
            clickEvent = { action = "suggest_command", value = "/denicker note " .. name .. " " }
        }}
    }))
end

local function onIgnoreChat(message)
    local blockedName = message:match("^Blocked (.+)%.$")
    if blockedName then
        pendingBlocks[blockedName] = os.time()
        promptForNote(blockedName)
        return
    end

    local removedName = message:match("^Removed (.+) from your ignore list%.$")
    if removedName then
        local currentName = findIgnoreEntry(removedName)
        if currentName then
            ignoreEntries[currentName] = nil
            saveIgnoreEntries()
        end
        return
    end

    if message:match("^Removed all blocked players%.?$") then
        ignoreEntries = {}
        saveIgnoreEntries()
        return
    end

    local page, totalPages = message:match("Blocked Players %(Page (%d+) of (%d+)%)")
    if page then
        onListPageHeader(tonumber(page), tonumber(totalPages))
        return
    end

    if listParse.active then
        local name = message:match("^%d+%.%s+(.+)$")
        if name then
            table.insert(listParse.names, name)
            restartListParseTimer()
        elseif message:match("^%-%-%-%-") then
            finalizeListParse()
        end
    end
end

-- Nick detection

local function parseSkinData(player, team)
    local uuid = player.uuid
    local name = player.name
    local properties = player.properties

    if not properties then
        local playerInfo = starfish.players.getInfo(uuid)
        if playerInfo then
            properties = playerInfo.properties
        end
    end

    if not properties then return end

    local textureProp = nil
    for i = 1, #properties do
        if properties[i].name == "textures" then
            textureProp = properties[i]
            break
        end
    end

    if not textureProp or not textureProp.value then return end

    local skinDataJson = starfish.base64.decode(textureProp.value)
    if not skinDataJson then return end

    local success, skinData = pcall(json.decode, skinDataJson)
    if not success or not skinData then return end

    if not skinData.textures or not skinData.textures.SKIN then return end

    local url = skinData.textures.SKIN.url
    if not url then return end

    local hash = url:match("[^/]+$")
    local prefix = team and team.prefix or ""
    local suffix = team and team.suffix or ""
    local teamFormattedName = prefix .. name .. suffix

    if KNOWN_NICK_SKINS[hash] then
        starfish.debug("Unresolved nick: " .. name)
        if getConfig("showUnresolvedNicks.enabled", true) then
            sendAlert(teamFormattedName, nil)
        end
        setNickDisplayName(uuid, name, nil)
        return
    end

    local realName = skinData.profileName
    if realName and realName ~= name then
        starfish.debug("Resolved nick: " .. name .. " -> " .. realName)
        resolvedNicks[name] = realName
        starfish.events.emit("denicker:nick_resolved", {
            nickName = name,
            realName = realName,
            uuid = uuid
        })
        sendCubelifyMessage(realName)
        sendAlert(teamFormattedName, realName)
        setNickDisplayName(uuid, name, realName)

        local _, entry = findIgnoreEntry(realName)
        if entry then
            ignoreAlert("§6" .. realName .. " §7is on your ignore list §8(added " .. formatAge(entry.addedAt) .. ")" .. formatNote(entry))
        end
    end
end

local function onPlayerInfo(event)
    if event.action ~= 0 then return end

    local players = event.players or {}
    for _, playerData in ipairs(players) do
        if playerData.name and type(playerData.name) == "string" then
            local uuid = playerData.uuid
            if uuid and #uuid >= 15 and uuid:sub(15, 15) == "1" then
                if not parsed[uuid] then
                    local player = {
                        uuid = uuid,
                        name = playerData.name,
                        properties = playerData.properties
                    }

                    local team = starfish.players.getTeam(player.name)
                    if team then
                        teamDataReceived[player.name] = true
                        parseSkinData(player, team)
                        parsed[uuid] = true
                    else
                        pendingChecks[player.name] = player
                    end
                end
            end
        end
    end
end

local function onTeamUpdate(event)
    local mode = event.mode
    if mode == 0 or mode == 2 or mode == 3 then
        for playerName, player in pairs(pendingChecks) do
            local team = starfish.players.getTeam(playerName)
            if team then
                teamDataReceived[playerName] = true
                parseSkinData(player, team)
                parsed[player.uuid] = true
                pendingChecks[playerName] = nil
            end
        end
    end
end

-- Event wiring

local function onRespawn(event)
    clearDisplayNames()
    reset()
end

local function onPluginRestored(event)
    if event.pluginName == "denicker" then
        parsed = {}
        pendingChecks = {}
        teamDataReceived = {}
    end
end

local function reapplyDisplayNames()
    if not getConfig("modifyDisplayNames.enabled", true) then
        return
    end
    for uuid, data in pairs(nickDisplayNames) do
        local nickSuffix
        if data.realName then
            nickSuffix = " §c(" .. data.realName .. ")"
        else
            nickSuffix = " §c[NICK]"
        end
        starfish.display.prependSuffix(uuid, nickSuffix)
    end
end

local function onConfigChanged(event)
    if event.plugin ~= "denicker" then
        return
    end

    if event.key == "modifyDisplayNames.enabled" then
        if event.value == false then
            clearDisplayNames()
        else
            reapplyDisplayNames()
        end
    end

    if event.key == "enabled" then
        if event.value == false then
            clearDisplayNames()
            reset()
        end
    end
end

local function onChat(event)
    if event.position == 2 then return end
    onIgnoreChat(stripColors(event.message or ""))
end

starfish.events.on("player_info", onPlayerInfo)
starfish.events.on("scoreboard_team", onTeamUpdate)
starfish.events.on("chat", onChat)
starfish.events.on("respawn", onRespawn)
starfish.events.on("plugin_restored", onPluginRestored)
starfish.events.on("config_changed", onConfigChanged)

ignoreEntries = starfish.config.get("ignoreEntries") or {}

-- Commands

starfish.commands.register("sync", {
    description = "Sync your ignore list by paging through /ignore list"
}, function()
    syncing = true
    starfish.chat.send(starfish.chat.prefix("§7Syncing ignore list..."))
    starfish.chat.sendToServer("/ignore list 1")
end)

starfish.commands.register("changed", {
    description = "Show ignore list entries whose name changed since they were added"
}, function()
    local changed = {}
    for name, entry in pairs(ignoreEntries) do
        if entry.originalName and entry.originalName ~= name then
            table.insert(changed, { name = name, entry = entry })
        end
    end

    if #changed == 0 then
        starfish.chat.send(starfish.chat.prefix("§7No nick changes detected yet."))
        return
    end

    table.sort(changed, function(a, b)
        return (a.entry.addedAt or 0) < (b.entry.addedAt or 0)
    end)

    starfish.chat.send(starfish.chat.prefix("§7Nick changes detected (" .. #changed .. "):"))
    for _, item in ipairs(changed) do
        starfish.chat.send(starfish.chat.prefix("§c" .. item.entry.originalName .. " §7→ §a" .. item.name .. " §8(added " .. formatAge(item.entry.addedAt) .. ")" .. formatNote(item.entry)))
    end
end)

starfish.commands.register("note", {
    description = "Record why you blocked a player (no text shows it, \"clear\" removes it)",
    arguments = {
        starfish.commands.arg("player", "Blocked player's name"),
        starfish.commands.greedy("text", "Note text")
    }
}, function(args)
    if #args == 0 then
        starfish.chat.send(starfish.chat.error("Usage: /denicker note <player> [text]"))
        return
    end

    local name, entry = findIgnoreEntry(args[1])
    if not entry then
        starfish.chat.send(starfish.chat.error(args[1] .. " is not on your tracked ignore list. Run /denicker sync first."))
        return
    end

    local text = table.concat(args, " ", 2)
    if text == "" then
        if entry.note then
            starfish.chat.send(starfish.chat.prefix("§c" .. name .. formatNote(entry)))
        else
            starfish.chat.send(starfish.chat.prefix("§7No note for §c" .. name .. "§7. Add one: §f/denicker note " .. name .. " <text>"))
        end
        return
    end

    if text == "clear" then
        entry.note = nil
        saveIgnoreEntries()
        starfish.chat.send(starfish.chat.success("Cleared the note for " .. name .. "."))
        return
    end

    entry.note = text
    saveIgnoreEntries()
    starfish.chat.send(starfish.chat.success("Noted for " .. name .. ": §7\"" .. text .. "\""))
end)

starfish.commands.register("list", {
    description = "List tracked ignore entries with their notes"
}, function()
    local entries = {}
    for name, entry in pairs(ignoreEntries) do
        table.insert(entries, { name = name, entry = entry })
    end

    if #entries == 0 then
        starfish.chat.send(starfish.chat.prefix("§7No tracked players. Run /denicker sync to import your ignore list."))
        return
    end

    table.sort(entries, function(a, b)
        return (a.entry.addedAt or 0) < (b.entry.addedAt or 0)
    end)

    starfish.chat.send(starfish.chat.prefix("§7Tracked ignore list (" .. #entries .. "):"))
    for _, item in ipairs(entries) do
        local renamed = ""
        if item.entry.originalName and item.entry.originalName ~= item.name then
            renamed = " §8(was " .. item.entry.originalName .. ")"
        end
        starfish.chat.send(starfish.chat.prefix("§c" .. item.name .. renamed .. " §8(added " .. formatAge(item.entry.addedAt) .. ")" .. formatNote(item.entry)))
    end
end)

-- Exports

starfish.api.export("isNicked", function(playerName)
    for uuid, data in pairs(nickDisplayNames) do
        if data.nickName == playerName then
            return true
        end
    end
    return false
end)

starfish.api.export("getRealName", function(nickName)
    return resolvedNicks[nickName]
end)

starfish.api.export("getNickedPlayers", function()
    local result = {}
    for uuid, data in pairs(nickDisplayNames) do
        table.insert(result, {
            uuid = uuid,
            nickName = data.nickName,
            realName = data.realName
        })
    end
    return result
end)

starfish.api.export("isIgnored", function(name)
    if not name then return false end
    return findIgnoreEntry(name) ~= nil
end)

starfish.api.export("getIgnoreEntry", function(name)
    if not name then return nil end
    local currentName, entry = findIgnoreEntry(name)
    if not entry then return nil end
    return { name = currentName, addedAt = entry.addedAt, originalName = entry.originalName, note = entry.note }
end)

starfish.api.export("getIgnoreEntries", function()
    local result = {}
    for name, entry in pairs(ignoreEntries) do
        result[name] = { addedAt = entry.addedAt, originalName = entry.originalName, note = entry.note }
    end
    return result
end)
