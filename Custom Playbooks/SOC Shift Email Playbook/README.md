# SOC Shift Email Playbook

This playbook is designed to be triggered automatically every 8 hours when the SOC analyst shift is over. It will provide a comprehensive list of incidents along with their statuses, closure time, and check if any incidents are breaching the SLA (Service Level Agreement).

<img src="EmailScreenshot.png" alt="Sample Email">

To simplify the deployment process, you can leverage the convenience of a one-click deployment using the Azure Deploy button:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fusamasaleem620%2FMicrosoft-Sentinel%2Fmain%2FCustom%2520Playbooks%2FSOC%2520Shift%2520Email%2520Playbook%2Fazuredeploy.json)
