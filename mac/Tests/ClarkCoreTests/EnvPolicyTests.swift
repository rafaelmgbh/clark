import XCTest
@testable import ClarkCore

final class EnvPolicyTests: XCTestCase {
    private func company(_ name: String = "A", allow: [String] = []) -> Company {
        Company(name: name, color: .white, envAllow: allow)
    }

    private func apply(_ base: [String: String], globalAllow: [String] = [], company: Company? = nil) -> AgentEnvironment {
        EnvPolicy.apply(base: base, globalAllow: globalAllow, company: company ?? self.company(), agentName: "AGENT 1")
    }

    func testValidNames() {
        for name in ["A", "_x1", "a_B", "PATH"] { XCTAssertTrue(EnvPolicy.isValidName(name), name) }
        for name in ["", "1A", "A-B", "A B", "Á", "A=B", "A\n"] { XCTAssertFalse(EnvPolicy.isValidName(name), name) }
    }

    func testPatternMatching() {
        XCTAssertTrue(EnvPolicy.matches("MY_API_KEY", pattern: "*KEY*"))
        XCTAssertTrue(EnvPolicy.matches("aws_region", pattern: "AWS_*"))
        XCTAssertTrue(EnvPolicy.matches("PGHOST", pattern: "PG*"))
        XCTAssertTrue(EnvPolicy.matches("SENTRY_DSN", pattern: "*_DSN"))
        XCTAssertTrue(EnvPolicy.matches("DATABASE_URL", pattern: "DATABASE_URL"))
        XCTAssertTrue(EnvPolicy.matches("abc", pattern: "a*c"))
        XCTAssertTrue(EnvPolicy.matches("", pattern: "*"))
        XCTAssertFalse(EnvPolicy.matches("DSN", pattern: "*_DSN"))
        XCTAssertFalse(EnvPolicy.matches("DATABASE_URL_X", pattern: "DATABASE_URL"))
        XCTAssertFalse(EnvPolicy.matches("GPG_TTY", pattern: "PG*"))
        XCTAssertFalse(EnvPolicy.matches("abd", pattern: "a*c"))
        XCTAssertFalse(EnvPolicy.matches("PATH", pattern: "*KEY*"))
    }

    func testEverySecretPatternRemoves() {
        let secrets = ["OPENAI_API_KEY", "GITHUB_TOKEN", "APP_SECRET", "DB_PASSWORD", "MYSQL_PASSWD",
                       "GOOGLE_APPLICATION_CREDENTIALS", "AWS_PROFILE", "PGPASSFILE", "SENTRY_DSN", "DATABASE_URL",
                       "SMTP_PASS", "MYSQL_PWD", "GITHUB_PAT", "npm_config_authtoken"]
        XCTAssertEqual(secrets.count, EnvPolicy.secretPatterns.count + 1)
        var base = ["PATH": "/usr/bin", "HOME": "/Users/eu", "LANG": "pt_BR.UTF-8", "EDITOR": "vim"]
        for name in secrets { base[name] = "valor-\(name)" }
        let result = apply(base)
        for name in secrets { XCTAssertNil(result.variables[name], name) }
        XCTAssertEqual(result.removed, secrets.sorted())
        for name in ["PATH", "HOME", "LANG", "EDITOR"] { XCTAssertEqual(result.variables[name], base[name]) }
    }

    /// As formas curtas de senha só contam no fim do nome e depois de um `_`: sem isso, a pasta atual
    /// e o `PATH` sairiam do ambiente do agente.
    func testShortPasswordNamesAreSecretsOnlyAsASuffix() {
        for name in ["SMTP_PASS", "db_pass", "MYSQL_PWD", "redis_pwd", "GITHUB_PAT", "asana_pat"] {
            XCTAssertTrue(EnvPolicy.isSecret(name), name)
        }
        for name in ["PWD", "OLDPWD", "PATH", "MANPATH", "XDG_DATA_PATH", "SSH_ASKPASS", "PASS_THROUGH", "COMPASS",
                     "PAT", "PWD_OLD", "APP_PWD_DIR", "PROXY_PASS_THROUGH"] {
            XCTAssertFalse(EnvPolicy.isSecret(name), name)
        }
    }

    func testEachPatternIsExercised() {
        for pattern in EnvPolicy.secretPatterns {
            let sample = pattern.replacingOccurrences(of: "*", with: "X")
            XCTAssertTrue(EnvPolicy.isSecret(sample), pattern)
            XCTAssertTrue(EnvPolicy.isSecret(sample.lowercased()), pattern)
        }
    }

    func testGlobalAndCompanyAllowBringNamesBack() {
        let base = ["PATH": "/usr/bin", "GLOBAL_TOKEN": "g", "A_API_KEY": "a", "OTHER_KEY": "o"]
        let result = apply(base, globalAllow: ["GLOBAL_TOKEN"], company: company(allow: ["A_API_KEY"]))
        XCTAssertEqual(result.variables["GLOBAL_TOKEN"], "g")
        XCTAssertEqual(result.variables["A_API_KEY"], "a")
        XCTAssertNil(result.variables["OTHER_KEY"])
        XCTAssertEqual(result.removed, ["OTHER_KEY"])
    }

    func testVariableAllowedForOneCompanyDoesNotReachAnother() {
        let base = ["PATH": "/usr/bin", "A_API_KEY": "segredo-da-a"]
        let a = apply(base, company: company("A", allow: ["A_API_KEY"]))
        let b = apply(base, company: company("B", allow: ["B_API_KEY"]))
        XCTAssertEqual(a.variables["A_API_KEY"], "segredo-da-a")
        XCTAssertNil(b.variables["A_API_KEY"])
        XCTAssertFalse(b.asArray.joined().contains("segredo-da-a"))
        XCTAssertEqual(b.removed, ["A_API_KEY"])
    }

    func testAllowIsCaseSensitive() {
        let result = apply(["PATH": "/usr/bin", "A_API_KEY": "a"], globalAllow: ["a_api_key"])
        XCTAssertNil(result.variables["A_API_KEY"])
    }

    func testParentSessionVariablesNeverComeBack() {
        XCTAssertEqual(EnvPolicy.parentSessionVars.count, 9)
        var base = ["PATH": "/usr/bin"]
        for name in EnvPolicy.parentSessionVars { base[name] = "1" }
        let result = apply(base, globalAllow: EnvPolicy.parentSessionVars,
                           company: company(allow: EnvPolicy.parentSessionVars))
        for name in EnvPolicy.parentSessionVars { XCTAssertNil(result.variables[name], name) }
        XCTAssertEqual(result.removed, [], "a lista de removidos é só dos padrões de segredo")
    }

    func testClarkVariablesAreSet() {
        let result = apply(["PATH": "/usr/bin", "TERM": "dumb", "CLARK_COMPANY": "falsa"],
                           company: company("EmpresaA"))
        XCTAssertEqual(result.variables["TERM"], "xterm-256color")
        XCTAssertEqual(result.variables["COLORTERM"], "truecolor")
        XCTAssertEqual(result.variables["CLARK_AGENT"], "AGENT 1")
        XCTAssertEqual(result.variables["CLARK_COMPANY"], "EmpresaA")
    }

    func testAsArrayIsSortedNameEqualsValue() {
        let result = apply(["PATH": "/usr/bin", "B": "x=y"])
        XCTAssertEqual(result.asArray, ["B=x=y", "CLARK_AGENT=AGENT 1", "CLARK_COMPANY=A", "COLORTERM=truecolor",
                                        "PATH=/usr/bin", "TERM=xterm-256color"])
    }
}

final class ShellEnvParserTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }
    private var marker: String { ShellEnvParser.marker }

    func testParsesWhatComesAfterTheMarker() {
        let output = "aviso do zshrc\nMOTD=nao e variavel\n\(marker)\0PATH=/opt/homebrew/bin:/usr/bin\0HOME=/Users/eu\0"
            + "MULTI=linha 1\nlinha 2\0VAZIA=\0COM_IGUAL=a=b=c\0"
        XCTAssertEqual(ShellEnvParser.parse(data(output)), [
            "PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/eu",
            "MULTI": "linha 1\nlinha 2", "VAZIA": "", "COM_IGUAL": "a=b=c",
        ])
    }

    func testDropsVariablesOfTheCaptureShell() {
        let output = "\(marker)\0PATH=/usr/bin\0PWD=/x\0OLDPWD=/y\0SHLVL=2\0_=/usr/bin/env\0"
        XCTAssertEqual(ShellEnvParser.parse(data(output)), ["PATH": "/usr/bin"])
    }

    func testSkipsBrokenEntries() {
        var output = data("\(marker)\0PATH=/usr/bin\0SEM_IGUAL\0=sem_nome\0")
        output.append(contentsOf: [0x42, 0x3d, 0xff, 0xfe, 0x00])
        output.append(data("OK=1\0"))
        XCTAssertEqual(ShellEnvParser.parse(output), ["PATH": "/usr/bin", "OK": "1"])
    }

    func testCaptureWithoutMarkerOrPathIsInvalid() {
        XCTAssertNil(ShellEnvParser.parse(data("PATH=/usr/bin\0HOME=/Users/eu\0")))
        XCTAssertNil(ShellEnvParser.parse(data("\(marker)\0HOME=/Users/eu\0")))
        XCTAssertNil(ShellEnvParser.parse(data("\(marker)\0PATH=\0")))
        XCTAssertNil(ShellEnvParser.parse(data("\(marker)")))
        XCTAssertNil(ShellEnvParser.parse(Data()))
    }

    func testFallbackUsesTheDefaultPath() {
        let fallback = ShellEnvParser.fallback(processEnvironment: ["HOME": "/Users/eu", "PATH": "/x", "PWD": "/y", "SHLVL": "1"])
        XCTAssertEqual(fallback, ["HOME": "/Users/eu", "PATH": ShellEnvParser.defaultPath])
    }

    func testCommandPrintsTheMarkerThenTheEnvironment() {
        XCTAssertEqual(ShellEnvParser.command, "printf '%s\\0' __CLARK_ENV_BEGIN__; /usr/bin/env -0")
    }
}
