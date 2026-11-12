import Layout from '@theme/Layout';

export default function Privacy() {
  return (
    <Layout title="Datenschutz / Privacy">
      <main className="container margin-vert--lg">
        <h1>Datenschutz / Privacy</h1>
        <section lang="de" aria-labelledby="datenschutz">
          <h2 id="datenschutz">Datenschutz</h2>
          <p>
            Verantwortlich für diese Website ist Robert Schäfer. Die Kontaktdaten
            stehen im <a href="https://roschaefer.de/de/impressum/">Impressum</a>.
          </p>
          <p>
            <strong>Hosting.</strong> Diese Website wird bei Netlify gehostet.
            Netlify verarbeitet Zugriffsdaten wie Ihre IP-Adresse. Weitere
            Informationen finden Sie in
            der <a href="https://www.netlify.com/privacy/">Datenschutzerklärung
            von Netlify (Englisch)</a>.
          </p>
          <p>
            <strong>Besuchsstatistik.</strong> <a href="https://www.goatcounter.com/help/privacy">GoatCounter</a> zählt
            Seitenaufrufe ohne Cookies oder Tracking-IDs. IP-Adressen und
            vollständige User-Agent-Angaben werden nicht dauerhaft gespeichert.
            Der Erfassungsendpunkt dieser Website leitet technische Besuchsdaten
            an GoatCounter weiter.
          </p>
        </section>
        <section lang="en" aria-labelledby="privacy">
          <h2 id="privacy">Privacy</h2>
          <p>
            Responsible for this site: Robert Schäfer, contact details in
            the <a href="https://roschaefer.de/en/imprint/">imprint</a>.
          </p>
          <p>
            <strong>Hosting.</strong> Netlify hosts this site. Netlify
            processes access data such as your IP address, see
            the <a href="https://www.netlify.com/privacy/">Netlify
            privacy statement</a>.
          </p>
          <p>
            <strong>Analytics.</strong> <a href="https://www.goatcounter.com/help/privacy">GoatCounter</a> counts
            which pages are visited, without cookies or tracking IDs. It does
            not permanently store IP addresses or full user agents. The collection
            endpoint on this site forwards technical visit data to GoatCounter.
          </p>
        </section>
      </main>
    </Layout>
  );
}
